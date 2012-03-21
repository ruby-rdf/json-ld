require 'open-uri'

module JSON::LD
  ##
  # A JSON-LD processor implementing the JsonLdProcessor interface.
  #
  # This API provides a clean mechanism that enables developers to convert JSON-LD data into a a variety of output formats that
  # are easier to work with in various programming languages. If a JSON-LD API is provided in a programming environment, the
  # entirety of the following API must be implemented.
  #
  # @see http://json-ld.org/spec/latest/json-ld-api/#the-application-programming-interface
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class API
    attr_accessor :value
    attr_accessor :context

    ##
    # Initialize the API, reading in any document and setting global options
    #
    # @param [#read, Hash, Array] input
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param [Hash] options
    # @yield [api]
    # @yieldparam [API]
    def initialize(input, context, options = {})
      @options = options
      @value = input.respond_to?(:read) ? JSON.parse(input.read) : input
      @context = EvaluationContext.new(options)
      @context = @context.parse(context) if context
      yield(self) if block_given?
    end
    
    ##
    # Expands the given input according to the steps in the Expansion Algorithm. The input must be copied, expanded and returned
    # if there are no errors. If the expansion fails, an appropriate exception must be thrown.
    #
    # @param [#read, Hash, Array] input
    #   The JSON-LD object to copy and perform the expansion upon.
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext]
    # @return [Hash, Array]
    #   The expanded JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#expansion-algorithm
    def self.expand(input, context = nil, options = {})
      result = nil
      API.new(input, context, options) do |api|
        result = api.expand(api.value, nil, api.context)
      end
      result
    end
    
    ##
    # Expand an Array or Object given an active context and performing local context expansion.
    #
    # @param [Array, Hash] input
    # @param [RDF::URI] predicate
    # @param [EvaluationContext] context
    # @return [Array, Hash]
    def expand(input, predicate, context)
      debug("expand") {"input: #{input.class}, predicate: #{predicate.inspect}, context: #{context.inspect}"}
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        depth {input.map {|v| expand(v, predicate, context)}}
      when Hash
        # Merge context
        context = context.parse(input['@context']) if input['@context']
      
        result = Hash.ordered
        input.each do |key, value|
          debug("expand") {"#{key}: #{value.inspect}"}
          expanded_key = context.mapping(key) || key
          case expanded_key
          when '@context'
            # Ignore in output
          when '@id', '@type'
            # If the key is @id or @type and the value is a string, expand the value according to IRI Expansion.
            result[expanded_key] = case value
            when String then context.expand_iri(value, :position => :subject, :depth => @depth).to_s
            else depth { expand(value, predicate, context) }
            end
            debug("expand") {" => #{result[expanded_key].inspect}"}
          when '@value', '@language'
            raise ProcessingError::Lossy, "Value of #{expanded_key} must be a string, was #{value.inspect}" unless value.is_a?(String)
            result[expanded_key] = value
            debug("expand") {" => #{result[expanded_key].inspect}"}
          else
            # 2.2.3) Otherwise, if the key is not a keyword, expand the key according to IRI Expansion rules and set as active property.
            unless key[0,1] == '@'
              predicate = context.expand_iri(key, :position => :predicate, :depth => @depth)
              expanded_key = predicate.to_s
            end

            # 2.2.4) If the value is an array, and active property is subject to @list expansion,
            #   replace the value with a new key-value key where the key is @list and value set to the current value.
            value = {"@list" => value} if value.is_a?(Array) && context.list(predicate)
            
            value = case value
            # 2.2.5) If the value is an array, process each item in the array recursively using this algorithm,
            #   passing copies of the active context and active property
            # 2.2.6) If the value is an object, process the object recursively using this algorithm,
            #   passing copies of the active context and active property.
            when Array, Hash then depth {expand(value, predicate, context)}
            else
              # 2.2.7) Otherwise, expand the value according to the Value Expansion rules, passing active property.
              context.expand_value(predicate, value, :position => :object, :depth => @depth)
            end
            result[expanded_key] = value
            debug("expand") {" => #{value.inspect}"}
          end
        end
        result
      else
        # 2.3) Otherwise, expand the value according to the Value Expansion rules, passing active property.
        context.expand_value(predicate, input, :position => :object, :depth => @depth)
      end
    end

    ##
    # Compacts the given input according to the steps in the Compaction Algorithm. The input must be copied, compacted and
    # returned if there are no errors. If the compaction fails, an appropirate exception must be thrown.
    #
    # If no context is provided, the input document is compacted using the top-level context of the document
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to copy and perform the compaction upon.
    # @param [IO, Hash, Array] context
    #   The base context to use when compacting the input.
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext, ProcessingError]
    # @return [Hash]
    #   The compacted JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#compaction-algorithm
    def self.compact(input, context = nil, options = {})
      expanded = result = nil

      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      API.new(input, nil, options) do |api|
        expanded = api.expand(api.value, nil, api.context)
      end

      API.new(expanded, context, options) do |api|
        result = api.compact(api.value, nil)

        # xxx) Add the given context to the output
        result = case result
        when Hash then api.context.serialize.merge(result)
        when Array then api.context.serialize.merge("@id" => result)
        end
      end
      result
    end

    ##
    # Compact an expanded Array or Hash given an active property and a context.
    #
    # @param [Array, Hash] input
    # @param [RDF::URI] predicate (nil)
    # @param [EvaluationContext] context
    # @return [Array, Hash]
    def compact(input, predicate = nil)
      debug("compact") {"input: #{input.class}, predicate: #{predicate.inspect}"}
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        debug("compact") {"Array[#{input.length}]"}
        depth {input.map {|v| compact(v, predicate)}}
      when Hash
        result = Hash.ordered
        input.each do |key, value|
          debug("compact") {"#{key}: #{value.inspect}"}
          compacted_key = context.alias(key)
          debug("compact") {" => compacted key: #{compacted_key.inspect}"} unless compacted_key == key

          case key
          when '@id', '@type'
            # If the key is @id or @type
            result[compacted_key] = case value
            when String, RDF::Value
              # If the value is a string, compact the value according to IRI Compaction.
              context.compact_iri(value, :position => :subject, :depth => @depth).to_s
            when Hash
              # Otherwise, if value is an object containing only the @id key, the compacted value
              # if the result of performing IRI Compaction on that value.
              if value.keys == ["@id"]
                context.compact_iri(value["@id"], :position => :subject, :depth => @depth).to_s
              else
                depth { compact(value, predicate) }
              end
            else
              # Otherwise, the compacted value is the result of performing this algorithm on the value
              # with the current active property.
              depth { compact(value, predicate) }
            end
            debug("compact") {" => compacted value: #{result[compacted_key].inspect}"}
          else
            # Otherwise, if the key is not a keyword, set as active property and compact according to IRI Compaction.
            unless key[0,1] == '@'
              predicate = RDF::URI(key)
              compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)
              debug("compact") {" => compacted key: #{compacted_key.inspect}"}
            end

            # If the value is an object
            compacted_value = if value.is_a?(Hash)
              if value.keys == ['@id'] || value['@value']
                # If the value contains only an @id key or the value contains a @value key, the compacted value
                # is the result of performing Value Compaction on the value.
                debug("compact") {"keys: #{value.keys.inspect}"}
                context.compact_value(predicate, value, :depth => @depth)
              elsif value.keys == ['@list'] && context.list(predicate)
                # Otherwise, if the value contains only a @list key, and the active property is subject to list coercion,
                # the compacted value is the result of performing this algorithm on that value.
                debug("compact") {"list"}
                depth {compact(value['@list'], predicate)}
              else
                # Otherwise, the compacted value is the result of performing this algorithm on the value
                debug("compact") {"object"}
                depth {compact(value, predicate)}
              end
            elsif value.is_a?(Array)
              # Otherwise, if the value is an array, the compacted value is the result of performing this algorithm on the value.
              debug("compact") {"array"}
              depth {compact(value, predicate)}
            else
              # Otherwise, the value is already compacted.
              debug("compact") {"value"}
              value
            end
            debug("compact") {" => compacted value: #{compacted_value.inspect}"}
            result[compacted_key || key] = compacted_value
          end
        end
        result
      else
        # For other types, the compacted value is the input value
        debug("compact") {input.class.to_s}
        input
      end
    end

    ##
    # Frames the given input using the frame according to the steps in the Framing Algorithm. The input is used to build the
    # framed output and is returned if there are no errors. If there are no matches for the frame, null must be returned.
    # Exceptions must be thrown if there are errors.
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to copy and perform the framing on.
    # @param [IO, Hash, Array] frame
    #   The frame to use when re-arranging the data.
    # @param  [Hash{Symbol => Object}] options
    # @option options [Boolean] :object_embed (true)
    #   a flag specifying that objects should be directly embedded in the output,
    #   instead of being referred to by their IRI.
    # @option options [Boolean] :explicit_inclusion (false)
    #   a flag specifying that for properties to be included in the output,
    #   they must be explicitly declared in the framing context.
    # @option options [Boolean] :omit_missing_props (false)
    #   a flag specifying that properties that are missing from the JSON-LD
    #   input should be omitted from the output.
    # @raise [InvalidFrame]
    # @return [Hash]
    #   The framed JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#framing-algorithm
    def self.frame(input, frame, options = {})
      expanded_frame = result = nil
      match_limit = 0
      framing_context = {
        :object_embed => true,
        :explicit_inclusion => false,
        :omit_missing_props => false
      }.merge(options)

      # Expand the input frame
      API.new(frame, nil, options) do |api|
        expanded_frame = api.expand(api.value, nil, api.context)
      end

      API.new(input, nil, options) do |api|
        normalized_input = api.normalize(api.value, nil)
        result = api.frame(normalized_input, expanded_frame, framing_context)
      end
      result
    end

    ##
    # Frame input.
    #
    # @param [Array] normalized_input
    # @param [Array, Hash] expanded_frame
    # @param [Hash{Symbol => Boolean}] framing_context
    # @return [Array, Hash]
    def frame(normalized_input, expanded_frame, framing_context)
      # 2) Generate a list of frames by processing the expanded frame
      match_limit, list_of_frames, result = case expanded_frame
      when []
        # 2.2) If the expanded frame is an empty array, place an empty object into the list of frames,
        # set the JSON-LD output to an array, and set match limit to -1.
        [-1, [Hash.new], Array.new]
      when Array
        # 2.3) If the expanded frame is a non-empty array,
        # add each item in the expanded frame into the list of frames,
        # set the JSON-LD output to an array, and set match limit to -1
        [-1, expanded_frame, Array.new]
      else
        # 2.1) If the expanded frame is not an array, set match limit to 1,
        # place the expanded frame into the list of frames,
        # and set the JSON-LD output to null.
        [1, [expanded_frame], nil]
      end

      # 3) Create a match array for each expanded frame
      list_of_frames.each do |expanded_frame|
        # Halt if match_limit is zero
        last if match_limit == 0
        raise InvalidFrame::Syntax, "Expanded Frame must be an object, was #{expanded_frame.class}" unless expanded_frame.is_a?(Hash)
        
        # Add each matching item from the normalized input to the matches array and decrement the match limit by 1 if:
      end
    end

    ##
    # Normalizes the given input according to the steps in the Normalization Algorithm. The input must be copied, normalized and
    # returned if there are no errors. If the compaction fails, null must be returned.
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to copy and perform the normalization upon.
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext]
    # @return [Hash]
    #   The normalized JSON-LD document
    def self.normalize(input, object, context = nil, options = {})
    end

    ##
    # Processes the input according to the RDF Conversion Algorithm, calling the provided tripleCallback for each triple generated.
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to process when outputting triples.
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext]
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    # @return [Hash]
    #   The normalized JSON-LD document
    def self.triples(input, object, context = nil, options = {})
    end
    
  private
    # Add debug event to debug array, if specified
    #
    # @param [String] message
    # @yieldreturn [String] appended to message, to allow for lazy-evaulation of message
    def debug(*args)
      return unless ::JSON::LD.debug? || @options[:debug]
      list = args
      list << yield if block_given?
      message = " " * (@depth || 0) * 2 + (list.empty? ? "" : list.join(": "))
      puts message if JSON::LD::debug?
      @options[:debug] << message if @options[:debug].is_a?(Array)
    end

    # Increase depth around a method invocation
    def depth(options = {})
      old_depth = @depth || 0
      @depth = (options[:depth] || old_depth) + 1
      ret = yield
      @depth = old_depth
      ret
    end
  end
end

