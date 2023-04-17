# frozen_string_literal: true

require 'set'

module JSON
  module LD
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
      # @param [String] property (nil)
      #   The parent property.
      # @param [Hash{String => Object}] parent (nil)
      #   Parent subject or top-level array
      # @param [Boolean] ordered (true)
      #   Ensure output objects have keys ordered properly
      # @param [Hash{Symbol => Object}] options ({})
      # @raise [JSON::LD::InvalidFrame]
      def frame(state, subjects, frame, parent: nil, property: nil, ordered: false, **options)
        # Validate the frame
        validate_frame(frame)
        frame = frame.first if frame.is_a?(Array)

        # Get values for embedOn and explicitOn
        flags = {
          embed: get_frame_flag(frame, options, :embed),
          explicit: get_frame_flag(frame, options, :explicit),
          requireAll: get_frame_flag(frame, options, :requireAll)
        }

        # Get link for current graph
        link = state[:link][state[:graph]] ||= {}

        # Create a set of matched subjects by filtering subjects by checking the map of flattened subjects against frame
        # This gives us a hash of objects indexed by @id
        matches = filter_subjects(state, subjects, frame, flags)

        # For each id and node from the set of matched subjects ordered by id
        matches.keys.opt_sort(ordered: ordered).each do |id|
          subject = matches[id]

          # NOTE: In order to treat each top-level match as a compartmentalized result, clear the unique embedded subjects map when the property is nil, which only occurs at the top-level.
          if property.nil?
            state[:uniqueEmbeds] = { state[:graph] => {} }
          else
            state[:uniqueEmbeds][state[:graph]] ||= {}
          end

          if flags[:embed] == '@link' && link.key?(id)
            # add existing linked subject
            add_frame_output(parent, property, link[id])
            next
          end

          output = { '@id' => id }
          link[id] = output

          if %w[@first @last].include?(flags[:embed]) && context.processingMode('json-ld-1.1')
            if @options[:validate]
              raise JSON::LD::JsonLdError::InvalidEmbedValue,
                "#{flags[:embed]} is not a valid value of @embed in 1.1 mode"
            end

            warn "[DEPRECATION] #{flags[:embed]}  is not a valid value of @embed in 1.1 mode.\n"
          end

          if !state[:embedded] && state[:uniqueEmbeds][state[:graph]].key?(id)
            # Skip adding this node object to the top-level, as it was included in another node object
            next
          elsif state[:embedded] &&
                (flags[:embed] == '@never' || creates_circular_reference(subject, state[:graph], state[:subjectStack]))
            # if embed is @never or if a circular reference would be created by an embed, the subject cannot be embedded, just add the reference; note that a circular reference won't occur when the embed flag is `@link` as the above check will short-circuit before reaching this point
            add_frame_output(parent, property, output)
            next
          elsif state[:embedded] &&
                %w[@first @once].include?(flags[:embed]) &&
                state[:uniqueEmbeds][state[:graph]].key?(id)

            # if only the first match should be embedded
            # Embed unless already embedded
            add_frame_output(parent, property, output)
            next
          elsif flags[:embed] == '@last'
            # if only the last match should be embedded
            # remove any existing embed
            remove_embed(state, id) if state[:uniqueEmbeds][state[:graph]].include?(id)
          end

          state[:uniqueEmbeds][state[:graph]][id] = {
            parent: parent,
            property: property
          }

          # push matching subject onto stack to enable circular embed checks
          state[:subjectStack] << { subject: subject, graph: state[:graph] }

          # Subject is also the name of a graph
          if state[:graphMap].key?(id)
            # check frame's "@graph" to see what to do next
            # 1. if it doesn't exist and state.graph === "@merged", don't recurse
            # 2. if it doesn't exist and state.graph !== "@merged", recurse
            # 3. if "@merged" then don't recurse
            # 4. if "@default" then don't recurse
            # 5. recurse
            recurse = false
            subframe = nil
            if frame.key?('@graph')
              subframe = frame['@graph'].first
              recurse = !['@merged', '@default'].include?(id)
              subframe = {} unless subframe.is_a?(Hash)
            else
              recurse = (state[:graph] != '@merged')
              subframe = {}
            end

            if recurse
              frame(state.merge(graph: id, embedded: false), state[:graphMap][id].keys, [subframe], parent: output,
                property: '@graph', **options)
            end
          end

          # If frame has `@included`, recurse over its sub-frame
          if frame['@included']
            frame(state.merge(embedded: false), subjects, frame['@included'], parent: output, property: '@included',
  **options)
          end

          # iterate over subject properties in order
          subject.keys.opt_sort(ordered: ordered).each do |prop|
            objects = subject[prop]

            # copy keywords to output
            if prop.start_with?('@')
              output[prop] = objects.dup
              next
            end

            # explicit is on and property isn't in frame, skip processing
            next if flags[:explicit] && !frame.key?(prop)

            # add objects
            objects.each do |o|
              subframe = Array(frame[prop]).first || create_implicit_frame(flags)

              if list?(o)
                subframe = frame[prop].first['@list'] if Array(frame[prop]).first.is_a?(Hash)
                subframe ||= create_implicit_frame(flags)
                # add empty list
                list = { '@list' => [] }
                add_frame_output(output, prop, list)

                src = o['@list']
                src.each do |oo|
                  if node_reference?(oo)
                    frame(state.merge(embedded: true), [oo['@id']], subframe, parent: list, property: '@list',
**options)
                  else
                    add_frame_output(list, '@list', oo.dup)
                  end
                end
              elsif node_reference?(o)
                # recurse into subject reference
                frame(state.merge(embedded: true), [o['@id']], subframe, parent: output, property: prop, **options)
              elsif value_match?(subframe, o)
                # Include values if they match
                add_frame_output(output, prop, o.dup)
              end
            end
          end

          # handle defaults in order
          frame.keys.opt_sort(ordered: ordered).each do |prop|
            if prop == '@type' && frame[prop].first.is_a?(Hash) && frame[prop].first.keys == %w[@default]
              # Treat this as a default
            elsif prop.start_with?('@')
              next
            end

            # if omit default is off, then include default values for properties that appear in the next frame but are not in the matching subject
            n = frame[prop].first || {}
            omit_default_on = get_frame_flag(n, options, :omitDefault)
            if !omit_default_on && !output[prop]
              preserve = as_array(n.fetch('@default', '@null').dup)
              output[prop] = [{ '@preserve' => preserve }]
            end
          end

          # If frame has @reverse, embed identified nodes having this subject as a value of the associated property.
          frame.fetch('@reverse', {}).each do |reverse_prop, subframe|
            state[:subjects].each do |r_id, node|
              next unless Array(node[reverse_prop]).any? { |v| v['@id'] == id }

              # Node has property referencing this subject
              # recurse into  reference
              (output['@reverse'] ||= {})[reverse_prop] ||= []
              frame(state.merge(embedded: true), [r_id], subframe, parent: output['@reverse'][reverse_prop],
                property: property, **options)
            end
          end

          # add output to parent
          add_frame_output(parent, property, output)

          # pop matching subject from circular ref-checking stack
          state[:subjectStack].pop
        end
        # end
      end

      ##
      # Recursively find and count blankNode identifiers.
      # @return [Hash{String => Integer}]
      def count_blank_node_identifiers(input)
        {}.tap do |results|
          count_blank_node_identifiers_internal(input, results)
        end
      end

      def count_blank_node_identifiers_internal(input, results)
        case input
        when Array
          input.each { |o| count_blank_node_identifiers_internal(o, results) }
        when Hash
          input.each do |_k, v|
            count_blank_node_identifiers_internal(v, results)
          end
        when String
          if input.start_with?('_:')
            results[input] ||= 0
            results[input] += 1
          end
        end
      end

      ##
      # Prune BNode identifiers recursively
      #
      # @param [Array, Hash] input
      # @param [Array<String>] bnodes_to_clear
      # @return [Array, Hash]
      def prune_bnodes(input, bnodes_to_clear)
        case input
        when Array
          # If, after replacement, an array contains only the value null remove the value, leaving an empty array.
          input.map { |o| prune_bnodes(o, bnodes_to_clear) }.compact
        when Hash
          output = {}
          input.each do |key, value|
            if context.expand_iri(key) == '@id' && bnodes_to_clear.include?(value)
              # Don't add this to output, as it is pruned as being superfluous
            else
              output[key] = prune_bnodes(value, bnodes_to_clear)
            end
          end
          output
        else
          input
        end
      end

      ##
      # Replace @preserve keys with the values, also replace @null with null.
      #
      # @param [Array, Hash] input
      # @return [Array, Hash]
      def cleanup_preserve(input)
        case input
        when Array
          input.map! { |o| cleanup_preserve(o) }
        when Hash
          if input.key?('@preserve')
            # Replace with the content of `@preserve`
            cleanup_preserve(input['@preserve'].first)
          else
            input.transform_values do |v|
              cleanup_preserve(v)
            end
          end
        else
          input
        end
      end

      ##
      # Replace `@null` with `null`, removing it from arrays.
      #
      # @param [Array, Hash] input
      # @return [Array, Hash]
      def cleanup_null(input)
        case input
        when Array
          # If, after replacement, an array contains only the value null remove the value, leaving an empty array.
          input.map! { |o| cleanup_null(o) }.compact
        when Hash
          input.transform_values do |v|
            cleanup_null(v)
          end
        when '@null'
          # If the value from the key-pair is @null, replace the value with null
          nil
        else
          input
        end
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
        subjects.each_with_object({}) do |id, memo|
          subject = state[:graphMap][state[:graph]][id]
          memo[id] = subject if filter_subject(subject, frame, state, flags)
        end
      end

      ##
      # Returns true if the given node matches the given frame.
      #
      # Matches either based on explicit type inclusion where the node has any type listed in the frame. If the frame has empty types defined matches nodes not having a @type. If the frame has a type of {} defined matches nodes having any type defined.
      #
      # Otherwise, does duck typing, where the node must have any or all of the properties defined in the frame, depending on the `requireAll` flag.
      #
      # @param [Hash{String => Object}] subject the subject to check.
      # @param [Hash{String => Object}] frame the frame to check.
      # @param [Hash{Symbol => Object}] state Current framing state
      # @param [Hash{Symbol => Object}] flags the frame flags.
      #
      # @return [Boolean] true if the node matches, false if not.
      def filter_subject(subject, frame, state, flags)
        # Duck typing, for nodes not having a type, but having @id
        wildcard = true
        matches_some = false

        frame.each do |k, v|
          node_values = subject.fetch(k, [])

          case k
          when '@id'
            ids = v || []

            # Match on specific @id.
            match_this = case ids
            when [], [{}]
              # Match on no @id or any @id
              true
            else
              # Match on specific @id
              ids.include?(subject['@id'])
            end
            return match_this unless flags[:requireAll]
          when '@type'
            # No longer a wildcard pattern
            wildcard = false

            match_this = case v
            when []
              # Don't match with any @type
              return false unless node_values.empty?

              true
            when [{}]
              # Match with any @type
              !node_values.empty?
            else
              # Treat a map with @default like an empty map
              if v.first.is_a?(Hash) && v.first.keys == %w[@default]
                true
              else
                !(v & node_values).empty?
              end
            end
            return match_this unless flags[:requireAll]
          when /@/
            # Skip other keywords
            next
          else
            is_empty = v.empty?
            if (v = v.first)
              validate_frame(v)
              has_default = v.key?('@default')
            end

            # No longer a wildcard pattern if frame has any non-keyword properties
            wildcard = false

            # Skip, but allow match if node has no value for property, and frame has a default value
            next if node_values.empty? && has_default

            # If frame value is empty, don't match if subject has any value
            return false if !node_values.empty? && is_empty

            match_this = case
            when v.nil?
              # node does not match if values is not empty and the value of property in frame is match none.
              return false unless node_values.empty?

              true
            when v.is_a?(Hash) && (v.keys - FRAMING_KEYWORDS).empty?
              # node matches if values is not empty and the value of property in frame is wildcard (frame with properties other than framing keywords)
              !node_values.empty?
            when value?(v)
              # Match on any matching value
              node_values.any? { |nv| value_match?(v, nv) }
            when node?(v) || node_reference?(v)
              node_values.any? do |nv|
                node_match?(v, nv, state, flags)
              end
            when list?(v)
              vv = v['@list'].first
              node_values = if list?(node_values.first)
                node_values.first['@list']
              else
                false
              end
              if !node_values
                false # Lists match Lists
              elsif value?(vv)
                # Match on any matching value
                node_values.any? { |nv| value_match?(vv, nv) }
              elsif node?(vv) || node_reference?(vv)
                node_values.any? do |nv|
                  node_match?(vv, nv, state, flags)
                end
              else
                false
              end
            else
              false # No matching on non-value or node values
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
        unless frame.is_a?(Hash) || (frame.is_a?(Array) && frame.first.is_a?(Hash) && frame.length == 1)
          raise JsonLdError::InvalidFrame,
            "Invalid JSON-LD frame syntax; a JSON-LD frame must be an object: #{frame.inspect}"
        end
        frame = frame.first if frame.is_a?(Array)

        # Check values of @id and @type
        unless Array(frame['@id']) == [{}] || Array(frame['@id']).all? { |v| RDF::URI(v).valid? }
          raise JsonLdError::InvalidFrame,
            "Invalid JSON-LD frame syntax; invalid value of @id: #{frame['@id']}"
        end
        unless Array(frame['@type']).all? do |v|
                 (v.is_a?(Hash) && (v.keys - %w[@default]).empty?) || RDF::URI(v).valid?
               end
          raise JsonLdError::InvalidFrame,
            "Invalid JSON-LD frame syntax; invalid value of @type: #{frame['@type']}"
        end
      end

      # Checks the current subject stack to see if embedding the given subject would cause a circular reference.
      #
      # @param subject_to_embed the subject to embed.
      # @param graph the graph the subject to embed is in.
      # @param subject_stack the current stack of subjects.
      #
      # @return true if a circular reference would be created, false if not.
      def creates_circular_reference(subject_to_embed, graph, subject_stack)
        subject_stack[0..-2].any? do |subject|
          subject[:graph] == graph && subject[:subject]['@id'] == subject_to_embed['@id']
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
          when true then '@once'
          when false then '@never'
          when '@always', '@first', '@last', '@link', '@once', '@never' then rval
          else
            raise JsonLdError::InvalidEmbedValue,
              "Invalid JSON-LD frame syntax; invalid value of @embed: #{rval}"
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
        embeds = state[:uniqueEmbeds][state[:graph]]
        embed = embeds[id]
        property = embed[:property]

        # create reference to replace embed
        subject = { '@id' => id }

        if embed[:parent].is_a?(Array)
          # replace subject with reference
          embed[:parent].map! do |parent|
            compare_values(parent, subject) ? subject : parent
          end
        else
          parent = embed[:parent]
          # replace node with reference
          if parent[property].is_a?(Array)
            parent[property].reject! { |v| compare_values(v, subject) }
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
        {}.tap do |memo|
          flags.each_pair do |key, val|
            memo["@#{key}"] = [val]
          end
        end
      end

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
        v1 = value['@value']
        t1 = value['@type']
        l1 = value['@language']
        v2 = Array(pattern['@value'])
        t2 = Array(pattern['@type'])
        l2 = Array(pattern['@language']).map do |v|
          v.is_a?(String) ? v.downcase : v
        end
        return true if (v2 + t2 + l2).empty?
        return false unless v2.include?(v1) || v2 == [{}]
        return false unless t2.include?(t1) || (t1 && t2 == [{}]) || (t1.nil? && (t2 || []).empty?)
        return false unless l2.include?(l1.to_s.downcase) || (l1 && l2 == [{}]) || (l1.nil? && (l2 || []).empty?)

        true
      end

      FRAMING_KEYWORDS = %w[@default @embed @explicit @omitDefault @requireAll].freeze
    end
  end
end
