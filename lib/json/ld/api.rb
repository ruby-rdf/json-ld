require 'open-uri'
require 'json/ld/expand'
require 'json/ld/compact'
require 'json/ld/frame'
require 'json/ld/to_rdf'
require 'json/ld/from_rdf'

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
    include Expand
    include Compact
    include Triples
    include FromTriples
    include Frame

    attr_accessor :value
    attr_accessor :context

    ##
    # Initialize the API, reading in any document and setting global options
    #
    # @param [String, #read, Hash, Array] input
    # @param [String, #read,, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param [Hash] options
    # @yield [api]
    # @yieldparam [API]
    def initialize(input, context, options = {}, &block)
      @options = options
      @value = case input
      when Array, Hash then input.dup
      when IO, StringIO then JSON.parse(input.read)
      when String
        content = nil
        RDF::Util::File.open_file(input) {|f| content = JSON.parse(f)}
        content
      end
      @context = EvaluationContext.new(options)
      @context = @context.parse(context) if context
      
      if block_given?
        case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
        end
      end
    end
    
    ##
    # Expands the given input according to the steps in the Expansion Algorithm. The input must be copied, expanded and returned
    # if there are no errors. If the expansion fails, an appropriate exception must be thrown.
    #
    # The resulting `Array` is returned via the provided callback.
    #
    # Note that for Ruby, if the callback is not provided and a block is given, it will be yielded
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the expansion upon.
    # @param [String, #read, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param [Proc] callback (&block)
    #   Alternative to using block, with same parameters.
    # @param  [Hash{Symbol => Object}] options
    # @option options [Boolean] :base
    #   Base IRI to use when processing relative IRIs.
    # @raise [InvalidContext]
    # @yield jsonld
    # @yieldparam [Array<Hash>] jsonld
    #   The expanded JSON-LD document
    # @return [Array<Hash>]
    #   The expanded JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#expansion-algorithm
    def self.expand(input, context = nil, callback = nil, options = {})
      result = nil
      API.new(input, context, options) do |api|
        result = api.expand(api.value, nil, api.context)
      end

      # If, after the algorithm outlined above is run, the resulting element is an
      # JSON object with just a @graph property, element is set to the value of @graph's value.
      result = result['@graph'] if result.is_a?(Hash) && result.keys == %w(@graph)

      # Finally, if element is a JSON object, it is wrapped into an array.
      result = [result] unless result.is_a?(Array)
      callback.call(result) if callback
      yield result if block_given?
      result
    end

    ##
    # Compacts the given input according to the steps in the Compaction Algorithm. The input must be copied, compacted and
    # returned if there are no errors. If the compaction fails, an appropirate exception must be thrown.
    #
    # If no context is provided, the input document is compacted using the top-level context of the document
    #
    # The resulting `Hash` is returned via the provided callback.
    #
    # Note that for Ruby, if the callback is not provided and a block is given, it will be yielded
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the compaction upon.
    # @param [String, #read, Hash, Array] context
    #   The base context to use when compacting the input.
    # @param [Proc] callback (&block)
    #   Alternative to using block, with same parameters.
    # @param  [Hash{Symbol => Object}] options
    #   Other options passed to {#expand}
    # @option options [Boolean] :optimize (false)
    #   Perform further optimmization of the compacted output.
    #   (Presently, this is a noop).
    # @param  [Hash{Symbol => Object}] options
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The compacted JSON-LD document
    # @return [Hash]
    #   The compacted JSON-LD document
    # @raise [InvalidContext, ProcessingError]
    # @see http://json-ld.org/spec/latest/json-ld-api/#compaction-algorithm
    def self.compact(input, context, callback = nil, options = {})
      expanded = result = nil

      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      API.new(input, nil, options) do |api|
        expanded = api.expand(api.value, nil, api.context)

        # x) If no context provided, use context from input document
        context ||= api.value.fetch('@context', nil)
      end

      API.new(expanded, context, options) do |api|
        result = api.compact(api.value, nil)

        # xxx) Add the given context to the output
        result = case result
        when Hash then api.context.serialize.merge(result)
        when Array
          kwgraph = api.context.compact_iri('@graph', :quiet => true)
          api.context.serialize.merge(kwgraph => result)
        when String
          kwid = api.context.compact_iri('@id', :quiet => true)
          api.context.serialize.merge(kwid => result)
        end
      end
      callback.call(result) if callback
      yield result if block_given?
      result
    end

    ##
    # Frames the given input using the frame according to the steps in the Framing Algorithm. The input is used to build the
    # framed output and is returned if there are no errors. If there are no matches for the frame, null must be returned.
    # Exceptions must be thrown if there are errors.
    #
    # The resulting `Array` is returned via the provided callback.
    #
    # Note that for Ruby, if the callback is not provided and a block is given, it will be yielded
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the framing on.
    # @param [String, #read, Hash, Array] frame
    #   The frame to use when re-arranging the data.
    # @param [Proc] callback (&block)
    #   Alternative to using block, with same parameters.
    # @param  [Hash{Symbol => Object}] options
    #   Other options passed to {#expand}
    # @option options [Boolean] :embed (true)
    #   a flag specifying that objects should be directly embedded in the output,
    #   instead of being referred to by their IRI.
    # @option options [Boolean] :explicit (false)
    #   a flag specifying that for properties to be included in the output,
    #   they must be explicitly declared in the framing context.
    # @option options [Boolean] :omitDefault (false)
    #   a flag specifying that properties that are missing from the JSON-LD
    #   input should be omitted from the output.
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The framed JSON-LD document
    # @return [Array<Hash>]
    #   The framed JSON-LD document
    # @raise [InvalidFrame]
    # @see http://json-ld.org/spec/latest/json-ld-api/#framing-algorithm
    def self.frame(input, frame, callback = nil, options = {})
      result = nil
      match_limit = 0
      framing_state = {
        :embed       => true,
        :explicit    => false,
        :omitDefault => false,
        :embeds      => {},
      }
      framing_state[:embed] = options[:embed] if options.has_key?(:embed)
      framing_state[:explicit] = options[:explicit] if options.has_key?(:explicit)
      framing_state[:omitDefault] = options[:omitDefault] if options.has_key?(:omitDefault)

      # de-reference frame to create the framing object
      frame = frame.respond_to?(:read) ? JSON.parse(frame.read) : frame

      # Expand frame to simplify processing
      expanded_frame = API.expand(frame)
      
      # Expand input to simplify processing
      expanded_input = API.expand(input)

      # Initialize input using frame as context
      API.new(expanded_input, nil, options) do
        debug(".frame") {"context from frame: #{context.inspect}"}
        debug(".frame") {"expanded frame: #{expanded_frame.to_json(JSON_STATE)}"}
        debug(".frame") {"expanded input: #{value.to_json(JSON_STATE)}"}

        # Get framing subjects from expanded input, replacing Blank Node identifiers as necessary
        @subjects = Hash.ordered
        depth {get_framing_subjects(@subjects, value, BlankNodeNamer.new("t"))}
        debug(".frame") {"subjects: #{@subjects.to_json(JSON_STATE)}"}

        result = []
        frame(framing_state, @subjects.keys, expanded_frame[0], result, nil)
        debug(".frame") {"result: #{result.inspect}"}
        
        # Initalize context from frame
        @context = depth {@context.parse(frame['@context'])}
        # Compact result
        compacted = depth {compact(result, nil)}
        
        # xxx) Add the given context to the output
        result = case compacted
        when Hash then [context.serialize.merge(compacted)]
        when Array
          ctx = context.serialize
          compacted.map do |o|
            o = {"@id" => o} if o.is_a?(String)
            ctx.merge(o)
          end
        when String then [context.serialize.merge("@id" => compacted)]
        end
        
        result = cleanup_null(result)
      end

      callback.call(result) if callback
      yield result if block_given?
      result
    end

    ##
    # Processes the input according to the RDF Conversion Algorithm, calling the provided callback for each triple generated.
    #
    # Note that for Ruby, if the callback is not provided and a block is given, it will be yielded
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to process when outputting statements.
    # @param [String, #read, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param [Proc] callback (&block)
    #   Alternative to using block, with same parameteres.
    # @param [{Symbol,String => Object}] options
    #   Options passed to {#expand}
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext]
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    def self.toRDF(input, context = nil, callback = nil, options = {})
      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      expanded = expand(input, context, nil, options)

      API.new(expanded, nil, options) do |api|
        # Start generating statements
        api.statements("", api.value, nil, nil, nil) do |statement|
          callback.call(statement) if callback
          yield statement if block_given?
        end
      end
    end
    
    ##
    # Take an ordered list of RDF::Statements and turn them into a JSON-LD document.
    #
    # The resulting `Array` is returned via the provided callback.
    #
    # Note that for Ruby, if the callback is not provided and a block is given, it will be yielded
    #
    # @param [Array<RDF::Statement>] input
    # @param [Proc] callback (&block)
    #   Alternative to using block, with same parameteres.
    # @param  [Hash{Symbol => Object}] options
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The JSON-LD document in expanded form
    # @return [Array<Hash>]
    #   The JSON-LD document in expanded form
    def self.fromRDF(input, callback = nil, options = {})
      result = nil

      API.new(nil, nil, options) do |api|
        result = api.from_statements(input)
      end

      callback.call(result) if callback
      yield result if block_given?
      result
    end
  end
end

