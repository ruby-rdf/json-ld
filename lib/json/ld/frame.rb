# -*- encoding: utf-8 -*-
# frozen_string_literal: true
module JSON::LD
  module Frame
    include Utils

    ##
    # Frame input. Input is expected in expanded form, but frame is in compacted form.
    #
    # @param [Hash{Symbol => Object}] state
    #   Current framing state
    # @param [Array<String>] subjects
    #   The subjects to filter
    # @param [Hash{String => Object}] frame
    # @param [Hash{Symbol => Object}] options ({})
    # @option options [Hash{String => Object}] :parent (nil)
    #   Parent subject or top-level array
    # @option options [String] :property (nil)
    #   The parent property.
    # @raise [JSON::LD::InvalidFrame]
    def frame(state, subjects, frame, **options)
      parent, property = options[:parent], options[:property]
      # Validate the frame
      validate_frame(frame)
      frame = frame.first if frame.is_a?(Array)

      # Get values for embedOn and explicitOn
      flags = {
        embed: get_frame_flag(frame, options, :embed),
        explicit: get_frame_flag(frame, options, :explicit),
        requireAll: get_frame_flag(frame, options, :requireAll),
      }

      # Create a set of matched subjects by filtering subjects by checking the map of flattened subjects against frame
      # This gives us a hash of objects indexed by @id
      matches = filter_subjects(state, subjects, frame, flags)

      # For each id and node from the set of matched subjects ordered by id
      matches.keys.kw_sort.each do |id|
        subject = matches[id]

        # Note: In order to treat each top-level match as a compartmentalized result, clear the unique embedded subjects map when the property is None, which only occurs at the top-level.
        state = state.merge(uniqueEmbeds: {}) if property.nil?

        if flags[:embed] == '@link' && state[:link].has_key?(id)
          # add existing linked subject
          add_frame_output(parent, property, state[:link][id])
          next
        end

        output = {'@id' => id}
        state[:link][id] = output

        # if embed is @never or if a circular reference would be created by an embed, the subject cannot be embedded, just add the reference; note that a circular reference won't occur when the embed flag is `@link` as the above check will short-circuit before reaching this point
        if flags[:embed] == '@never' || creates_circular_reference(subject, state[:subjectStack])
          add_frame_output(parent, property, output)
          next
        end

        # if only the last match should be embedded
        if flags[:embed] == '@last'
          # remove any existing embed
          remove_embed(state, id) if state[:uniqueEmbeds].include?(id)
          state[:uniqueEmbeds][id] = {
            parent: parent,
            property: property
          }
        end

        # push matching subject onto stack to enable circular embed checks
        state[:subjectStack] << subject

        # iterate over subject properties in order
        subject.keys.kw_sort.each do |prop|
          objects = subject[prop]

          # copy keywords to output
          if prop.start_with?('@')
            output[prop] = objects.dup
            next
          end

          # explicit is on and property isn't in frame, skip processing
          next if flags[:explicit] && !frame.has_key?(prop)

          # add objects
          objects.each do |o|
            subframe = Array(frame[prop]).first || create_implicit_frame(flags)

            case
            when list?(o)
              # add empty list
              list = {'@list' => []}
              add_frame_output(output, prop, list)

              src = o['@list']
              src.each do |oo|
                if node_reference?(oo)
                  frame(state, [oo['@id']], subframe, options.merge(parent: list, property: '@list'))
                else
                  add_frame_output(list, '@list', oo.dup)
                end
              end
            when node_reference?(o)
              # recurse into subject reference
              frame(state, [o['@id']], subframe, options.merge(parent: output, property: prop))
            when value_match?(subframe, o)
              # Include values if they match
              add_frame_output(output, prop, o.dup)
            end
          end
        end

        # handle defaults in order
        frame.keys.kw_sort.reject {|p| p.start_with?('@')}.each do |prop|
          # if omit default is off, then include default values for properties that appear in the next frame but are not in the matching subject
          n = frame[prop].first || {}
          omit_default_on = get_frame_flag(n, options, :omitDefault)
          if !omit_default_on && !output[prop]
            preserve = n.fetch('@default', '@null').dup
            preserve = [preserve] unless preserve.is_a?(Array)
            output[prop] = [{'@preserve' => preserve}]
          end
        end

        # If frame has @reverse, embed identified nodes having this subject as a value of the associated property.
        frame.fetch('@reverse', {}).each do |reverse_prop, subframe|
          state[:subjects].each do |r_id, node|
            if Array(node[reverse_prop]).any? {|v| v['@id'] == id}
              # Node has property referencing this subject
              # recurse into  reference
              (output['@reverse'] ||= {})[reverse_prop] ||= []
              frame(state, [r_id], subframe, options.merge(parent: output['@reverse'][reverse_prop]))
            end
          end
        end

        # add output to parent
        add_frame_output(parent, property, output)

        # pop matching subject from circular ref-checking stack
        state[:subjectStack].pop()
      end
    end

    ##
    # Replace @preserve keys with the values, also replace @null with null
    #
    # @param [Array, Hash] input
    # @return [Array, Hash]
    def cleanup_preserve(input)
      result = case input
      when Array
        # If, after replacement, an array contains only the value null remove the value, leaving an empty array.
        input.map {|o| cleanup_preserve(o)}.compact
      when Hash
        output = Hash.new
        input.each do |key, value|
          if key == '@preserve'
            # replace all key-value pairs where the key is @preserve with the value from the key-pair
            output = cleanup_preserve(value)
          else
            v = cleanup_preserve(value)

            # Because we may have added a null value to an array, we need to clean that up, if we possible
            v = v.first if v.is_a?(Array) && v.length == 1 &&
              context.expand_iri(key) != "@graph" && context.container(key).nil?
            output[key] = v
          end
        end
        output
      when '@null'
        # If the value from the key-pair is @null, replace the value with nul
        nil
      else
        input
      end
      result
    end

    private

    ##
    # Returns a map of all of the subjects that match a parsed frame.
    #
    # @param [Hash{Symbol => Object}] state
    #   Current framing state
    # @param [Array<String>] subjects
    #   The subjects to filter
    # @param [Hash{String => Object}] frame
    # @param [Hash{Symbol => String}] flags the frame flags.
    #
    # @return all of the matched subjects.
    def filter_subjects(state, subjects, frame, flags)
      subjects.inject({}) do |memo, id|
        subject = state[:subjects][id]
        memo[id] = subject if filter_subject(subject, frame, state, flags)
        memo
      end
    end

    ##
    # Returns true if the given node matches the given frame.
    #
    # Matches either based on explicit type inclusion where the node has any type listed in the frame. If the frame has empty types defined matches nodes not having a @type. If the frame has a type of {} defined matches nodes having any type defined.
    #
    # Otherwise, does duck typing, where the node must have all of the properties defined in the frame.
    #
    # @param [Hash{String => Object}] subject the subject to check.
    # @param [Hash{String => Object}] frame the frame to check.
    # @param [Hash{Symbol => Object}] state Current framing state
    # @param [Hash{Symbol => Object}] flags the frame flags.
    #
    # @return [Boolean] true if the node matches, false if not.
    def filter_subject(subject, frame, state, flags)
      # Duck typing, for nodes not having a type, but having @id
      wildcard, matches_some = true, false

      frame.each do |k, v|
        node_values = subject.fetch(k, [])

        case k
        when '@id'
          ids = v || []

          # Match on specific @id.
          return ids.include?(subject['@id']) if !ids.empty? && ids != [{}]
          match_this = true
        when '@type'
          # No longer a wildcard pattern
          wildcard = false

          match_this = case v
          when []
            # Don't Match on no @type
            return false if !node_values.empty?
            true
          when [{}]
            # Match on wildcard @type
            !node_values.empty?
          else
            # Match on specific @type
            return !(v & node_values).empty?
            false
          end
        when /@/
          # Skip other keywords
          next
        else
          is_empty = v.empty?
          if v = v.first
            validate_frame(v)
            has_default = v.has_key?('@default')
            # Exclude framing keywords
            v = v.dup.delete_if {|kk,vv| %w(@default @embed @explicit @omitDefault @requireAll).include?(kk)}
          end


          # No longer a wildcard pattern if frame has any non-keyword properties
          wildcard = false

          # Skip, but allow match if node has no value for property, and frame has a default value
          next if node_values.empty? && has_default

          # If frame value is empty, don't match if subject has any value
          return false if !node_values.empty? && is_empty

          match_this = case v
          when nil
            # node does not match if values is not empty and the value of property in frame is match none.
            return false unless node_values.empty?
            true
          when {}
            # node matches if values is not empty and the value of property in frame is wildcard
            !node_values.empty?
          else
            if value?(v)
              # Match on any matching value
              node_values.any? {|nv| value_match?(v, nv)}
            elsif node?(v) || node_reference?(v)
              node_values.any? do |nv|
                node_match?(v, nv, state, flags)
              end
            else
              false # No matching on non-value or node values
            end
          end
        end

        # All non-defaulted values must match if @requireAll is set
        return false if !match_this && flags[:requireAll]

        matches_some ||= match_this
      end

      # return true if wildcard or subject matches some properties
      wildcard || matches_some
    end

    def validate_frame(frame)
      raise InvalidFrame::Syntax,
            "Invalid JSON-LD syntax; a JSON-LD frame must be an object: #{frame.inspect}" unless
        frame.is_a?(Hash) || (frame.is_a?(Array) && frame.first.is_a?(Hash) && frame.length == 1)
    end

    # Checks the current subject stack to see if embedding the given subject would cause a circular reference.
    # 
    # @param subject_to_embed the subject to embed.
    # @param subject_stack the current stack of subjects.
    # 
    # @return true if a circular reference would be created, false if not.
    def creates_circular_reference(subject_to_embed, subject_stack)
      subject_stack[0..-2].any? do |subject|
        subject['@id'] == subject_to_embed['@id']
      end
    end

    ##
    # Gets the frame flag value for the given flag name.
    # 
    # @param frame the frame.
    # @param options the framing options.
    # @param name the flag name.
    # 
    # @return the flag value.
    def get_frame_flag(frame, options, name)
      rval = frame.fetch("@#{name}", [options[name]]).first
      rval = rval.values.first if value?(rval)
      if name == :embed
        rval = case rval
        when true then '@last'
        when false then '@never'
        when '@always', '@never', '@link' then rval
        else '@last'
        end
      end
      rval
    end

    ##
    # Removes an existing embed.
    #
    # @param state the current framing state.
    # @param id the @id of the embed to remove.
    def remove_embed(state, id)
      # get existing embed
      embeds = state[:uniqueEmbeds];
      embed = embeds[id];
      property = embed[:property];

      # create reference to replace embed
      subject = {'@id' => id}

      if embed[:parent].is_a?(Array)
        # replace subject with reference
        embed[:parent].map! do |parent|
          compare_values(parent, subject) ? subject : parent
        end
      else
        parent = embed[:parent]
        # replace node with reference
        if parent[property].is_a?(Array)
          parent[property].reject! {|v| compare_values(v, subject)}
          parent[property] << subject
        elsif compare_values(parent[property], subject)
          parent[property] = subject
        end
      end

      # recursively remove dependent dangling embeds
      def remove_dependents(id, embeds)
        # get embed keys as a separate array to enable deleting keys in map
        embeds.each do |id_dep, e|
          p = e.fetch(:parent, {}) if e.is_a?(Hash)
          next unless p.is_a?(Hash)
          pid = p.fetch('@id', nil)
          if pid == id
            embeds.delete(id_dep)
            remove_dependents(id_dep, embeds)
          end
        end
      end

      remove_dependents(id, embeds)
    end

    ##
    # Adds framing output to the given parent.
    #
    # @param parent the parent to add to.
    # @param property the parent property, null for an array parent.
    # @param output the output to add.
    def add_frame_output(parent, property, output)
      if parent.is_a?(Hash)
        parent[property] ||= []
        parent[property] << output
      else
        parent << output
      end
    end

    # Creates an implicit frame when recursing through subject matches. If a frame doesn't have an explicit frame for a particular property, then a wildcard child frame will be created that uses the same flags that the parent frame used.
    #
    # @param [Hash] flags the current framing flags.
    # @return [Array<Hash>] the implicit frame.
    def create_implicit_frame(flags)
      flags.keys.inject({}) {|memo, key| memo["@#{key}"] = [flags[key]]; memo}
    end

  private
    # Node matches if it is a node, and matches the pattern as a frame
    def node_match?(pattern, value, state, flags)
      return false unless value['@id']
      node_object = state[:subjects][value['@id']]
      node_object && filter_subject(node_object, pattern, state, flags)
    end

    # Value matches if it is a value, and matches the value pattern.
    #
    # * `pattern` is empty
    # * @values are the same, or `pattern[@value]` is a wildcard, and
    # * @types are the same or `value[@type]` is not null and `pattern[@type]` is `{}`, or `value[@type]` is null and `pattern[@type]` is null or `[]`, and
    # * @languages are the same or `value[@language]` is not null and `pattern[@language]` is `{}`, or `value[@language]` is null and `pattern[@language]` is null or `[]`.
    def value_match?(pattern, value)
      v1, t1, l1 = value['@value'], value['@type'], value['@language']
      v2, t2, l2 = Array(pattern['@value']), Array(pattern['@type']), Array(pattern['@language'])
      return true if (v2 + t2 + l2).empty?
      return false unless v2.include?(v1) || v2 == [{}]
      return false unless t2.include?(t1) || t1 && t2 == [{}] || t1.nil? && (t2 || []) == []
      return false unless l2.include?(l1) || l1 && l2 == [{}] || l1.nil? && (l2 || []) == []
      true
    end
  end
end
