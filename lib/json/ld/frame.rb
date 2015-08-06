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
    def frame(state, subjects, frame, options = {})
      depth do
        parent, property = options[:parent], options[:property]
        # Validate the frame
        validate_frame(state, frame)
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

          if flags[:embed] == '@link' && state[:link].has_key?(id)
            # TODO: may want to also match an existing linked subject
            # against the current frame ... so different frames could
            # produce different subjects that are only shared in-memory
            # when the frames are the same

            # add existing linked subject
            add_frame_output(parent, property, state[:link][id])
            next
          end

          # Note: In order to treat each top-level match as a
          # compartmentalized result, clear the unique embedded subjects map
          # when the property is None, which only occurs at the top-level.
          state = state.merge(uniqueEmbeds: {}) if property.nil?

          output = {'@id' => id}
          state[:link][id] = output

          # if embed is @never or if a circular reference would be created
          # by an embed, the subject cannot be embedded, just add the
          # reference; note that a circular reference won't occur when the
          # embed flag is `@link` as the above check will short-circuit
          # before reaching this point
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
              case
              when list?(o)
                # add empty list
                list = {'@list' => []}
                add_frame_output(output, prop, list)

                src = o['@list']
                src.each do |oo|
                  if node_reference?(oo)
                    subframe = frame[prop].first['@list'] if frame[prop].is_a?(Array) && frame[prop].first.is_a?(Hash)
                    subframe ||= create_implicit_frame(flags)
                    frame(state, [oo['@id']], subframe, options.merge(parent: list, property: '@list'))
                  else
                    add_frame_output(list, '@list', oo.dup)
                  end
                end
              when node_reference?(o)
                # recurse into subject reference
                subframe = frame[prop] || create_implicit_frame(flags)
                frame(state, [o['@id']], subframe, options.merge(parent: output, property: prop))
              else
                # include other values automatically
                add_frame_output(output, prop, o.dup)
              end
            end
          end

          # handle defaults in order
          frame.keys.kw_sort.reject {|p| p.start_with?('@')}.each do |prop|
            # if omit default is off, then include default values for
            # properties that appear in the next frame but are not in
            # the matching subject
            n = frame[prop].first || {}
            omit_default_on = get_frame_flag(n, options, :omitDefault)
            if !omit_default_on && !output[prop]
              preserve = n.fetch('@default', '@null').dup
              preserve = [preserve] unless preserve.is_a?(Array)
              output[prop] = [{'@preserve' => preserve}]
            end
          end

          # add output to parent
          add_frame_output(parent, property, output)

          # pop matching subject from circular ref-checking stack
          state[:subjectStack].pop()
        end
      end
    end

    ##
    # Replace @preserve keys with the values, also replace @null with null
    #
    # @param [Array, Hash] input
    # @return [Array, Hash]
    def cleanup_preserve(input)
      depth do
        result = case input
        when Array
          # If, after replacement, an array contains only the value null remove the value, leaving an empty array.
          input.map {|o| cleanup_preserve(o)}.compact
        when Hash
          output = Hash.new(input.size)
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
    end

    private

    ##
    # Returns a map of all of the subjects that match a parsed frame.
    #
    # @param [Hash{Symbol => Object}] state
    #   Current framing state
    # @param [Hash{String => Hash}] subjects
    #   The subjects to filter
    # @param [Hash{String => Object}] frame
    # @param [Hash{Symbol => String}] flags the frame flags.
    #
    # @return all of the matched subjects.
    def filter_subjects(state, subjects, frame, flags)
      subjects.inject({}) do |memo, id|
        subject = state[:subjects][id]
        memo[id] = subject if filter_subject(subject, frame, flags)
        memo
      end
    end

    ##
    # Returns true if the given node matches the given frame.
    #
    # Matches either based on explicit type inclusion where the node
    # has any type listed in the frame. If the frame has empty types defined
    # matches nodes not having a @type. If the frame has a type of {} defined
    # matches nodes having any type defined.
    #
    # Otherwise, does duck typing, where the node must have all of the properties
    # defined in the frame.
    #
    # @param [Hash{String => Object}] subject the subject to check.
    # @param [Hash{String => Object}] frame the frame to check.
    # @param [Hash{Symbol => Object}] flags the frame flags.
    #
    # @return [Boolean] true if the node matches, false if not.
    def filter_subject(subject, frame, flags)
      types = frame.fetch('@type', [])
      raise InvalidFrame::Syntax, "frame @type must be an array: #{types.inspect}" unless types.is_a?(Array)
      subject_types = subject.fetch('@type', [])
      raise InvalidFrame::Syntax, "node @type must be an array: #{node_types.inspect}" unless subject_types.is_a?(Array)

      # check @type (object value means 'any' type, fall through to ducktyping)
      if !types.empty? &&
         !(types.length == 1 && types.first.is_a?(Hash))
        # If frame has an @type, use it for selecting appropriate nodes.
        return types.any? {|t| subject_types.include?(t)}
      else
        # Duck typing, for nodes not having a type, but having @id
        wildcard, matches_some = true, false

        frame.each do |k, v|
          case k
          when '@id'
            return false if v.is_a?(String) && subject['@id'] != v
            wildcard, matches_some = true, true
          when '@type'
            wildcard, matches_some = true, true
          when /^@/
          else
            wildcard = false

            # v == [] means do not match if property is present
            if subject.has_key?(k)
              return false if v == []
              matches_some = true
              next
            end

            # all properties must match to be a duck unless a @default is
            # specified
            has_default = v.is_a?(Array) && v.length == 1 && v.first.is_a?(Hash) && v.first.has_key?('@default')
            return false if flags[:requireAll] && !has_default
          end
        end

        # return true if wildcard or subject matches some properties
        wildcard || matches_some
      end
    end

    def validate_frame(state, frame)
      raise InvalidFrame::Syntax,
            "Invalid JSON-LD syntax; a JSON-LD frame must be an object: #{frame.inspect}" unless
        frame.is_a?(Hash) || (frame.is_a?(Array) && frame.first.is_a?(Hash) && frame.length == 1)
    end

    # Checks the current subject stack to see if embedding the given subject
    # would cause a circular reference.
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

        depth do
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

    # Creates an implicit frame when recursing through subject matches. If
    # a frame doesn't have an explicit frame for a particular property, then
    # a wildcard child frame will be created that uses the same flags that
    # the parent frame used.
    #
    # @param [Hash] flags the current framing flags.
    # @return [Array<Hash>] the implicit frame.
    def create_implicit_frame(flags)
      [flags.keys.inject({}) {|memo, key| memo["@#{key}"] = [flags[key]]; memo}]
    end
  end
end
