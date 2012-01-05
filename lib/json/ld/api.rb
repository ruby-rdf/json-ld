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
      json_state = JSON::State.new(
        :indent       => "  ",
        :space        => " ",
        :space_before => "",
        :object_nl    => "\n",
        :array_nl     => "\n"
      )
      result.to_json(json_state)
    end
    
    ##
    # Expand an Array or Object given an active context and performing local context expansion.
    #
    # @param [Array, Hash] input
    # @param [RDF::URI] predicate (nil)
    # @param [EvaluationContext] context
    # @return [Array, Hash]
    def expand(input, predicate = nil, context)
      debug("expand") {"input: #{input.class}, predicate: #{predicate.inspect}, context: #{context.inspect}"}
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        depth {input.map {|v| expand(v, predicate, context)}}
      when Hash
        # Merge context
        context = context.parse(input['@context']) if input['@context']
      
        result = Hash.new
        input.each do |key, value|
          debug("expand") {"#{key}: #{value.inspect}"}
          case key
          when '@context'
            # Ignore in output
          when '@id', '@type'
            # If the key is @id or @type and the value is a string, expand the value according to IRI Expansion.
            result[key] = case value
            when String then context.expand_iri(value, :position => :subject, :depth => @depth)
            else depth { expand(value, predicate, context) }
            end
            debug("expand") {" => #{result[key].inspect}"}
          when '@literal'
            raise ProcessingError::Lossy, "Value of @literal must be a string, was #{value.inspect}" unless value.is_a?(String)
            result[key] = value
            debug("expand") {" => #{result[key].inspect}"}
          else
            # 2.2.3) Otherwise, if the key is not a keyword, expand the key according to IRI Expansion rules and set as active property.
            predicate = context.expand_iri(key, :position => :predicate, :depth => @depth) unless key[0,1] == '@'
            
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
            result[key[0,1] == '@' ? key : predicate.to_s] = value
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

      API.new(input, nil, options) do |api|
        expanded = api.expand(api.value, nil, api.context)
      end

      API.new(expanded, context, options) do |api|
        # 1) Perform the Expansion Algorithm on the JSON-LD input.
        #    This removes any existing context to allow the given context to be cleanly applied.
        
        result = api.compact(api.value, nil)

        # xxx) Add the given context to the output
        result = api.context.serialize.merge(result)
      end
      json_state = JSON::State.new(
        :indent       => "  ",
        :space        => " ",
        :space_before => "",
        :object_nl    => "\n",
        :array_nl     => "\n"
      )
      result.to_json(json_state)
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
        result = Hash.new
        input.each do |key, value|
          debug("compact") {"#{key}: #{value.inspect}"}
          case key
          when '@id', '@type'
            # If the key is @id or @type
            result[key] = case value
            when String, RDF::Value
              # If the value is a string, compact the value according to IRI Compaction.
              context.compact_iri(value, :position => :subject, :depth => @depth)
            else
              # Otherwise, the compacted value is the result of performing this algorithm on the value
              # with the current active property.
              depth { compact(value, predicate) }
            end
            debug("compact") {" => #{result[key].inspect}"}
          else
            # Otherwise, if the key is not a keyword, set as active property and compact according to IRI Compaction.
            unless key[0,1] == '@'
              predicate = RDF::URI(key)
              compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)
              debug("compact") {" => compacted key: #{compacted_key.inspect}"}
            end

            # If the value is an object
            compacted_value = if value.is_a?(Hash)
              if value.keys == ['@id'] || value['@literal']
                # If the value contains only an @id key or the value contains a @literal key, the compacted value
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
    # @raise [InvalidFrame]
    # @return [Hash]
    #   The framed JSON-LD document
    def self.frame(input, frame, options = {})
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
