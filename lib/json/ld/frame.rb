module JSON::LD
  module Frame
    include Utils

    ##
    # Frame input. Input is expected in expanded form, but frame is in compacted form.
    #
    # @param [Hash{Symbol => Object}] state
    #   Current framing state
    # @param [Hash{String => Hash}] subjects
    #   Map of flattened subjects
    # @param [Hash{String => Object}] frame
    # @param [Hash{String => Object}] parent
    #   Parent subject or top-level array
    # @param [String] property
    #   Property referencing this frame, or null for array.
    # @raise [JSON::LD::InvalidFrame]
    def frame(state, subjects, frame, parent, property)
      raise ProcessingError, "why isn't @subjects a hash?: #{@subjects.inspect}" unless @subjects.is_a?(Hash)
      depth do
        debug("frame") {"state: #{state.inspect}"}
        debug("frame") {"subjects: #{subjects.keys.inspect}"}
        debug("frame") {"frame: #{frame.to_json(JSON_STATE)}"}
        debug("frame") {"parent: #{parent.to_json(JSON_STATE)}"}
        debug("frame") {"property: #{property.inspect}"}
        # Validate the frame
        validate_frame(state, frame)

        # Create a set of matched subjects by filtering subjects by checking the map of flattened subjects against frame
        # This gives us a hash of objects indexed by @id
        matches = filter_subjects(state, subjects, frame)
        debug("frame") {"matches: #{matches.keys.inspect}"}

        # Get values for embedOn and explicitOn
        embed = get_frame_flag(state, frame, 'embed');
        explicit = get_frame_flag(state, frame, 'explicit');
        debug("frame") {"embed: #{embed.inspect}, explicit: #{explicit.inspect}"}
      
        # For each id and subject from the set of matched subjects ordered by id
        matches.keys.sort.each do |id|
          element = matches[id]
          # If the active property is null, set the map of embeds in state to an empty map
          state = state.merge(:embeds => {}) if property.nil?

          output = {'@id' => id}
        
          # prepare embed meta info
          embedded_subject = {:parent => parent, :property => property}
        
          # If embedOn is true, and id is in map of embeds from state
          if embed && (existing = state[:embeds].fetch(id, nil))
            # only overwrite an existing embed if it has already been added to its
            # parent -- otherwise its parent is somewhere up the tree from this
            # embed and the embed would occur twice once the tree is added
            embed = false
          
            embed = if existing[:parent].is_a?(Array)
              # If existing has a parent which is an array containing a JSON object with @id equal to id, element has already been embedded and can be overwritten, so set embedOn to true
              existing[:parent].detect {|p| p['@id'] == id}
            else
              # Otherwise, existing has a parent which is a subject definition. Set embedOn to true if any of the items in parent property is a subject definition or subject reference for id because the embed can be overwritten
              existing[:parent].fetch(existing[:property], []).any? do |v|
                v.is_a?(Hash) && v.fetch('@id', nil) == id
              end
            end
            debug("frame") {"embed now: #{embed.inspect}"}

            # If embedOn is true, existing is already embedded but can be overwritten
            remove_embed(state, id) if embed
          end

          unless embed
            # not embedding, add output without any other properties
            add_frame_output(state, parent, property, output)
          else
            # Add embed to map of embeds for id
            state[:embeds][id] = embedded_subject
            debug("frame") {"add embedded_subject: #{embedded_subject.inspect}"}
        
            # Process each property and value in the matched subject as follows
            element.keys.sort.each do |prop|
              value = element[prop]
              if prop[0,1] == '@'
                # If property is a keyword, add property and a copy of value to output and continue with the next property from subject
                output[prop] = value.dup
                next
              end

              # If property is not in frame:
              unless frame.has_key?(prop)
                debug("frame") {"non-framed property #{prop}"}
                # If explicitOn is false, Embed values from subject in output using subject as element and property as active property
                embed_values(state, element, prop, output) unless explicit
                
                # Continue to next property
                next
              end
          
              # Process each item from value as follows
              value.each do |item|
                debug("frame") {"value property #{prop.inspect} == #{item.inspect}"}
                
                # FIXME: If item is a JSON object with the key @list
                if list?(item)
                  # create a JSON object named list with the key @list and the value of an empty array
                  list = {'@list' => []}
                  
                  # Append list to property in output
                  add_frame_output(state, output, prop, list)
                  
                  # Process each listitem in the @list array as follows
                  item['@list'].each do |listitem|
                    if subject_reference?(listitem)
                      itemid = listitem['@id']
                      debug("frame") {"list item of #{prop} recurse for #{itemid.inspect}"}

                      # If listitem is a subject reference process listitem recursively using this algorithm passing a new map of subjects that contains the @id of listitem as the key and the subject reference as the value. Pass the first value from frame for property as frame, list as parent, and @list as active property.
                      frame(state, {itemid => @subjects[itemid]}, frame[prop].first, list, '@list')
                    else
                      # Otherwise, append a copy of listitem to @list in list.
                      debug("frame") {"list item of #{prop} non-subject ref #{listitem.inspect}"}
                      add_frame_output(state, list, '@list', listitem)
                    end
                  end
                elsif subject_reference?(item)
                  # If item is a subject reference process item recursively
                  # Recurse into sub-objects
                  itemid = item['@id']
                  debug("frame") {"value property #{prop} recurse for #{itemid.inspect}"}
                  
                  # passing a new map as subjects that contains the @id of item as the key and the subject reference as the value. Pass the first value from frame for property as frame, output as parent, and property as active property
                  frame(state, {itemid => @subjects[itemid]}, frame[prop].first, output, prop)
                else
                  # Otherwise, append a copy of item to active property in output.
                  debug("frame") {"value property #{prop} non-subject ref #{item.inspect}"}
                  add_frame_output(state, output, prop, item)
                end
              end
            end

            # Process each property and value in frame in lexographical order, where property is not a keyword, as follows:
            frame.keys.sort.each do |prop|
              next if prop[0,1] == '@' || output.has_key?(prop)
              property_frame = frame[prop]
              debug("frame") {"frame prop: #{prop.inspect}. property_frame: #{property_frame.inspect}"}

              # Set property frame to the first item in value or a newly created JSON object if value is empty.
              property_frame = property_frame.first || {}

              # Skip to the next property in frame if property is in output or if property frame contains @omitDefault which is true or if it does not contain @omitDefault but the value of omit default flag true.
              next if output.has_key?(prop) || get_frame_flag(state, property_frame, 'omitDefault')

              # Set the value of property in output to a new JSON object with a property @preserve and a value that is a copy of the value of @default in frame if it exists, or the string @null otherwise
              default = property_frame.fetch('@default', '@null').dup
              default = [default] unless default.is_a?(Array)
              output[prop] = [{"@preserve" => default.compact}]
              debug("=>") {"add default #{output[prop].inspect}"}
            end
          
            # Add output to parent
            add_frame_output(state, parent, property, output)
          end
        end
      end
    end

    ##
    # Build hash of subjects used for framing. Also returns flattened representation
    # of input.
    #
    # @param [Hash{String => Hash}] subjects
    #   destination for mapped subjects and their Object representations
    # @param [Array, Hash] input
    #   JSON-LD in expanded form
    # @param [BlankNodeNamer] namer
    # @return
    #   input with subject definitions changed to references
    def get_framing_subjects(subjects, input, namer)
      depth do
        debug("framing subjects") {"input: #{input.inspect}"}
        case input
        when Array
          input.map {|o| get_framing_subjects(subjects, o, namer)}
        when Hash
          case
          when subject?(input) || subject_reference?(input)
            # Get name for subject, mapping old blank node identifiers to new
            name = blank_node?(input) ? namer.get_name(input.fetch('@id', nil)) : input['@id']
            debug("framing subjects") {"new subject: #{name.inspect}"} unless subjects.has_key?(name)
            subject = subjects[name] ||= {'@id' => name}

            # In property order
            input.keys.sort.each do |prop|
              value = input[prop]
              case prop
              when '@id'
                # Skip @id, already assigned
              when /^@/
                # Copy other keywords
                subject[prop] = value
              else
                case value
                when Hash
                  # Special case @list, which is not in expanded form
                  raise InvalidFrame::Syntax, "Unexpected hash value: #{value.inspect}" unless value.has_key?('@list')
                
                  # Map entries replacing subjects with subject references
                  subject[prop] = {"@list" =>
                    value['@list'].map {|o| get_framing_subjects(subjects, o, namer)}
                  }
                when Array
                  # Map array entries
                  subject[prop] = get_framing_subjects(subjects, value, namer)
                else
                  raise InvalidFrame::Syntax, "unexpected value: #{value.inspect}"
                end
              end
            end
            
            # Return as subject reference
            {"@id" => name}
          else
            # At this point, it's not a subject or a reference, just return input
            input
          end
        else
          # Returns equivalent representation
          input
        end
      end
    end

    ##
    # Flatten input, used in framing.
    #
    # This algorithm works by transforming input to statements, and then back to JSON-LD
    #
    # @return [Array{Hash}]
    def flatten
      debug("flatten")
      expanded = depth {self.expand(self.value, nil, context)}
      statements = []
      depth {self.statements("", expanded, nil, nil, nil ) {|s| statements << s}}
      debug("flatten") {"statements: #{statements.map(&:to_nquads).join("\n")}"}

      # Transform back to JSON-LD, not flattened
      depth {self.from_statements(statements)}
    end

    ##
    # Replace @preserve keys with the values, also replace @null with null
    #
    # @param [Array, Hash] input
    # @return [Array, Hash]
    def cleanup_preserve(input)
      depth do
        #debug("cleanup preserve") {input.inspect}
        result = case input
        when Array
          # If, after replacement, an array contains only the value null remove the value, leaving an empty array. 
          input.map {|o| cleanup_preserve(o)}.compact
        when Hash
          output = Hash.ordered
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
        #debug(" => ") {result.inspect}
        result
      end
    end

    private
    
    ##
    # Returns a map of all of the subjects that match a parsed frame.
    # 
    # @param state the current framing state.
    # @param subjects the set of subjects to filter.
    # @param frame the parsed frame.
    # 
    # @return all of the matched subjects.
    def filter_subjects(state, subjects, frame)
      subjects.dup.keep_if {|id, element| filter_subject(state, element, frame)}
    end

    ##
    # Returns true if the given subject matches the given frame.
    #
    # Matches either based on explicit type inclusion where the subject
    # has any type listed in the frame. If the frame has empty types defined
    # matches subjects not having a @type. If the frame has a type of {} defined
    # matches subjects having any type defined.
    #
    # Otherwise, does duck typing, where the subject must have all of the properties
    # defined in the frame.
    # 
    # @param [Hash{Symbol => Object}] state the current frame state.
    # @param [Hash{String => Object}] subject the subject to check.
    # @param [Hash{String => Object}] frame the frame to check.
    # 
    # @return true if the subject matches, false if not.
    def filter_subject(state, subject, frame)
      if types = frame.fetch('@type', nil)
        subject_types = subject.fetch('@type', [])
        raise InvalidFrame::Syntax, "frame @type must be an array: #{types.inspect}" unless types.is_a?(Array)
        raise InvalidFrame::Syntax, "subject @type must be an array: #{subject_types.inspect}" unless subject_types.is_a?(Array)
        # If frame has an @type, use it for selecting appropriate subjects.
        debug("frame") {"filter subject: #{subject_types.inspect} has any of #{types.inspect}"}

        # Check for type wild-card, or intersection
        types == [{}] ? !subject_types.empty? : subject_types.any? {|t| types.include?(t)}
      else
        # Duck typing, for subjects not having a type, but having @id
        
        # Subject matches if it has all the properties in the frame
        frame_keys = frame.keys.reject {|k| k[0,1] == '@'}
        subject_keys = subject.keys.reject {|k| k[0,1] == '@'}
        (frame_keys & subject_keys) == frame_keys
      end
    end

    def validate_frame(state, frame)
      raise InvalidFrame::Syntax,
            "Invalid JSON-LD syntax; a JSON-LD frame must be an object" unless frame.is_a?(Hash)
    end
    
    # Return value of @name in frame, or default from state if it doesn't exist
    def get_frame_flag(state, frame, name)
      !!(frame.fetch("@#{name}", [state[name.to_sym]]).first)
    end

    ##
    # Removes an existing embed.
    #
    # @param state the current framing state.
    # @param id the @id of the embed to remove.
    def remove_embed(state, id)
      debug("frame") {"remove embed #{id.inspect}"}
      # get existing embed
      embeds = state[:embeds];
      embed = embeds[id];
      parent = embed[:parent];
      property = embed[:property];

      # create reference to replace embed
      subject = {}
      subject['@id'] = id
      ref = {'@id' => id}
      
      # remove existing embed
      if subject?(parent)
        # replace subject with reference
        parent[property].map! do |v|
          v.is_a?(Hash) && v.fetch('@id', nil) == id ? ref : v
        end
      end

      # recursively remove dependent dangling embeds
      def remove_dependents(id, embeds)
        debug("frame") {"remove dependents for #{id}"}

        depth do
          # get embed keys as a separate array to enable deleting keys in map
          embeds.each do |id_dep, e|
            p = e.fetch(:parent, {}) if e.is_a?(Hash)
            next unless p.is_a?(Hash)
            pid = p.fetch('@id', nil)
            if pid == id
              debug("frame") {"remove #{id_dep} from embeds"}
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
    # @param state the current framing state.
    # @param parent the parent to add to.
    # @param property the parent property, null for an array parent.
    # @param output the output to add.
    def add_frame_output(state, parent, property, output)
      if parent.is_a?(Hash)
        debug("frame") { "add for property #{property.inspect}: #{output.inspect}"}
        parent[property] ||= []
        parent[property] << output
      else
        debug("frame") { "add top-level: #{output.inspect}"}
        parent << output
      end
    end
    
    ##
    # Embeds values for the given element and property into output.
    def embed_values(state, element, property, output)
      element[property].each do |o|
        # Get element @id, if this is an object
        sid = o['@id'] if subject_reference?(o)
        if sid
          unless state[:embeds].has_key?(sid)
            debug("frame") {"embed element #{sid.inspect}"}
            # Embed full element, if it isn't already embedded
            embed = {:parent => output, :property => property}
            state[:embeds][sid] = embed
          
            # Recurse into element
            s = @subjects.fetch(sid, {'@id' => sid})
            o = {}
            s.each do |prop, value|
              if prop[0,1] == '@'
                # Copy keywords
                o[prop] = s[prop].dup
              else
                depth do
                  debug("frame") {"embed property #{prop.inspect} value #{value.inspect}"}
                  embed_values(state, s, prop, o)
                end
              end
            end
          else
            debug("frame") {"don't embed element #{sid.inspect}"}
          end
        else
          debug("frame") {"embed property #{property.inspect}, value #{o.inspect}"}
        end
        add_frame_output(state, output, property, o.dup)
      end
    end
  end
end
