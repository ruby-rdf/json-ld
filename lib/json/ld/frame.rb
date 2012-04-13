module JSON::LD
  module Frame
    include Utils

    ##
    # Frame input. Input is expected in expanded form, but frame is in compacted form.
    #
    # @param [Hash{Symbol => Object}] state
    #   Current framing state
    # @param [Array<String>] subjects
    #   Set of subjects to be filtered
    # @param [Hash{String => Object}] frame
    # @param [Hash{String => Object}] parent
    #   Parent subject or top-level array
    # @param [String] property
    #   Property referencing this frame, or null for array.
    # @raise [JSON::LD::InvalidFrame]
    def frame(state, subjects, frame, parent, property)
      raise "why isn't @subjects a hash?: #{@subjects.inspect}" unless @subjects.is_a?(Hash)
      depth do
        debug("frame") {"state: #{state.inspect}"}
        debug("frame") {"subjects: #{subjects.inspect}"}
        debug("frame") {"frame: #{frame.inspect}"}
        debug("frame") {"parent: #{parent.inspect}"}
        debug("frame") {"property: #{property.inspect}"}
        # Validate the frame
        validate_frame(state, frame)

        # Filter out subjects matching the frame
        # This gives us a hash of objects indexed by @id
        matches = filter_subjects(state, subjects, frame)
        debug("frame") {"matches: #{matches.keys.inspect}"}

        # get flags for current frame
        embedOn = get_frame_flag(state, frame, 'embed');
        explicit = get_frame_flag(state, frame, 'explicit');
        debug("frame") {"embed: #{embedOn.inspect}, explicit: #{explicit.inspect}"}
      
        # Add matches to output
        matches.each do |id, subject|
          output = {}
          output['@id'] = id
        
          # prepare embed meta info
          embed = {:parent => parent, :property => property}
        
          # if embed is on and there is an existing embed
          if embedOn && (existing = state[:embeds].fetch(id, nil))
            # only overwrite an existing embed if it has already been added to its
            # parent -- otherwise its parent is somewhere up the tree from this
            # embed and the embed would occur twice once the tree is added
            embedOn = false
          
            embedOn = if existing[:parent].is_a?(Array)
              # exisitng embed's parent is an array
              # perform embedding if the subject has already been emitted
              existing[:parent].detect {|p| output == p}
            else
              # Existing embed's parent is an object,
              # perform embedding if the property already includes output
              has_value?(existing[:parent], existing[:property], output)
            end
            debug("frame") {"embed now: #{embedOn.inspect}"}

            # existing embed has already been added, so allow an overwrite
            remove_embed(state, id) if embedOn
          end

          unless embedOn
            # not embedding, add output without any other properties
            add_frame_output(state, parent, property, output)
          else
            # add embed meta info
            state[:embeds][id] = embed
            debug("frame") {"add embed: #{embed.inspect}"}
        
            # iterate over subject properties
            subject.each do |prop, value|
              if prop[0,1] == '@'
                # Copy keywords
                output[prop] = subject[prop].dup
                next
              end

              # Embed values if explcit is off and the frame doesn't have the property
              unless frame.has_key?(prop)
                debug("frame") {"non-framed property #{prop}"}
                embed_values(state, subject, prop, output) unless explicit
                next
              end
          
              # only look at values which are references to subjects
              value.each do |o|
                debug("frame") {"framed property #{prop.inspect} == #{o.inspect}"}
                oid = o.fetch('@id', o) if o.is_a?(Hash)
                if oid && @subjects.has_key?(oid)
                  # Recurse into sub-objects
                  debug("frame") {"framed property #{prop} recurse for #{oid.inspect}"}
                  frame(state, [oid], frame[prop].first, output, prop)
                else
                  # include other values automatically
                  debug("frame") {"framed property #{prop} non-subject ref #{o.inspect}"}
                  add_frame_output(state, output, prop, o)
                end
              end
            end

            frame.each do |prop, property_frame|
              # Skip keywords
              next if prop[0,1] == '@' || output.has_key?(prop)
              debug("frame") {"prop: #{prop.inspect}. property_frame: #{property_frame.inspect}"}

              # If the key is not in the item, add the key to the item and set the associated value to an
              # empty array if the match frame key's value is an empty array or null otherwise
              property_frame = property_frame.first || {}

              # if omit default is off, then include default values for properties
              # that appear in the next frame but are not in the matching subject
              next if get_frame_flag(state, property_frame, 'omitDefault')
              default = property_frame.fetch('@default', nil)
              default ||= '@null' if property_frame.empty?
              output[prop] = [default].compact
            end
          
            # Add output to parent
            add_frame_output(state, parent, property, output)
          end
          output
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
          
            input.each do |prop, value|
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
                  raise "Unexpected hash value: #{value.inspect}" unless value.has_key?('@list')
                
                  # Map entries replacing subjects with subject references
                  subject[prop] = {"@list" =>
                    value['@list'].map {|o| get_framing_subjects(subjects, o, namer)}
                  }
                when Array
                  # Map array entries
                  subject[prop] = get_framing_subjects(subjects, value, namer)
                else
                  raise "unexpected value: #{value.inspect}"
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
      depth {self.from_statements(statements, BlankNodeNamer.new("t"))}
    end

    ##
    # Cleanup output after framing, replacing @null with nil
    #
    # @param [Array, Hash] input
    # @return [Array, Hash]
    def cleanup_null(input)
      case input
      when Array
        input.map {|o| cleanup_null(o)}
      when Hash
        output = Hash.ordered
        input.each do |key, value|
          output[key] = cleanup_null(value)
        end
        output
      when '@null'
        nil
      else
        input
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
      subjects.inject({}) do |memo, id|
        s = @subjects.fetch(id, nil)
        memo[id] = s if filter_subject(state, s, frame)
        memo
      end
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
        raise "frame @type must be an array: #{types.inspect}" unless types.is_a?(Array)
        raise "subject @type must be an array: #{subject_types.inspect}" unless subject_types.is_a?(Array)
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

    # Does the subject property have the specified value
    # Expects that properties are in expanded (array) form
    def has_value?(subject, property, value)
      subject.fetch(property, []).any? {|v| compare_values(v, value)}
    end

    ##
    # Compares two JSON-LD values for equality. Two JSON-LD values will be
    # considered equal if:
    #
    # 1. They are both primitives of the same type and value.
    # 2. They are both @values with the same @value, @type, and @language, OR
    # 3. They both have @ids they are the same.
    #
    # @param v1 the first value.
    # @param v2 the second value.
    #
    # @return true if v1 and v2 are considered equal, false if not.
    def compare_values(v1, v2)
      case v1
      when Hash
        v2.is_a?(Hash) && (
          v1.has_key?('@id') ?
            (v1['@id'] == v2['@id']) :
            %(@value @type @language).all? {|p| v1.fetch(p, false) == v2.fetch(p, false)}
        )
      else
        v1 == v2
      end
    end

    def validate_frame(state, frame)
      raise JSON::LD::InvalidFrame::Syntax,
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
      if parent.is_a?(Array)
        # replace subject with reference
        i = parent.index(subject)
        parent[i] = ref if i
      else 
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
    # Embeds values for the given subject and property into output.
    def embed_values(state, subject, property, output)
      subject[property].each do |o|
        # Get subject @id, if this is an object
        sid = o.fetch('@id', nil) if o.is_a?(Hash)
        if sid
          unless state[:embeds].has_key?(sid)
            debug("frame") {"embed subject #{sid.inspect}"}
            # Embed full subject, if it isn't already embedded
            embed = {:parent => output, :property => property}
            state[:embeds][sid] = embed
          
            # Recurse into subject
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
            debug("frame") {"don't embed subject #{sid.inspect}"}
          end
          
          add_frame_output(state, output, property, o)
        else
          debug("frame") {"embed property #{property.inspect}, value #{o.inspect}"}
          add_frame_output(state, output, property, o.dup)
        end
      end
    end
  end
end
