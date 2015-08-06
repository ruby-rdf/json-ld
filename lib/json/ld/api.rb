require 'openssl'
require 'json/ld/expand'
require 'json/ld/compact'
require 'json/ld/flatten'
require 'json/ld/frame'
require 'json/ld/to_rdf'
require 'json/ld/from_rdf'

begin
  require 'jsonlint'
rescue LoadError
end

module JSON::LD
  ##
  # A JSON-LD processor based on the JsonLdProcessor interface.
  #
  # This API provides a clean mechanism that enables developers to convert JSON-LD data into a a variety of output formats that are easier to work with in various programming languages. If a JSON-LD API is provided in a programming environment, the entirety of the following API must be implemented.
  #
  # Note that the API method signatures are somewhat different than what is specified, as the use of Futures and explicit callback parameters is not as relevant for Ruby-based interfaces.
  #
  # @see http://json-ld.org/spec/latest/json-ld-api/#the-application-programming-interface
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class API
    include Expand
    include Compact
    include ToRDF
    include Flatten
    include FromRDF
    include Frame

    # Options used for open_file
    OPEN_OPTS = {
      headers: {"Accept" => "application/ld+json, application/json"}
    }

    # Current input
    # @!attribute [rw] input
    # @return [String, #read, Hash, Array]
    attr_accessor :value

    # Input evaluation context
    # @!attribute [rw] context
    # @return [JSON::LD::Context]
    attr_accessor :context

    # Current Blank Node Namer
    # @!attribute [r] namer
    # @return [JSON::LD::BlankNodeNamer]
    attr_reader :namer

    ##
    # Initialize the API, reading in any document and setting global options
    #
    # @param [String, #read, Hash, Array] input
    # @param [String, #read, Hash, Array, JSON::LD::Context] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @option options [String, #to_s] :base
    #   The Base IRI to use when expanding the document. This overrides the value of `input` if it is a _IRI_. If not specified and `input` is not an _IRI_, the base IRI defaults to the current document IRI if in a browser context, or the empty string if there is no document context.
    #   If not specified, and a base IRI is found from `input`, options[:base] will be modified with this value.
    # @option options [Boolean] :compactArrays (true)
    #   If set to `true`, the JSON-LD processor replaces arrays with just one element with that element during compaction. If set to `false`, all arrays will remain arrays even if they have just one element.
    # @option options [Proc] :documentLoader
    #   The callback of the loader to be used to retrieve remote documents and contexts. If specified, it must be used to retrieve remote documents and contexts; otherwise, if not specified, the processor's built-in loader must be used. See {documentLoader} for the method signature.
    # @option options [String, #read, Hash, Array, JSON::LD::Context] :expandContext
    #   A context that is used to initialize the active context when expanding a document.
    # @option options [Boolean, String, RDF::URI] :flatten
    #   If set to a value that is not `false`, the JSON-LD processor must modify the output of the Compaction Algorithm or the Expansion Algorithm by coalescing all properties associated with each subject via the Flattening Algorithm. The value of `flatten must` be either an _IRI_ value representing the name of the graph to flatten, or `true`. If the value is `true`, then the first graph encountered in the input document is selected and flattened.
    # @option options [String] :processingMode ("json-ld-1.0")
    #   If set to "json-ld-1.0", the JSON-LD processor must produce exactly the same results as the algorithms defined in this specification. If set to another value, the JSON-LD processor is allowed to extend or modify the algorithms defined in this specification to enable application-specific optimizations. The definition of such optimizations is beyond the scope of this specification and thus not defined. Consequently, different implementations may implement different optimizations. Developers must not define modes beginning with json-ld as they are reserved for future versions of this specification.
    # @option options [String] :produceGeneralizedRdf (false)
    #   Unless the produce generalized RDF flag is set to true, RDF triples containing a blank node predicate are excluded from output.
    # @option options [Boolean] :useNativeTypes (false)
    #   If set to `true`, the JSON-LD processor will use native datatypes for expression xsd:integer, xsd:boolean, and xsd:double values, otherwise, it will use the expanded form.
    # @option options [Boolean] :useRdfType (false)
    #   If set to `true`, the JSON-LD processor will treat `rdf:type` like a normal property instead of using `@type`.
    # @option options [Boolean] :rename_bnodes (true)
    #   Rename bnodes as part of expansion, or keep them the same.
    # @option options [Boolean]  :unique_bnodes   (false)
    #   Use unique bnode identifiers, defaults to using the identifier which the node was originall initialized with (if any).
    # @option options [Boolean]  :simple_compact_iris   (false)
    #   When compacting IRIs, do not use terms with expanded term definitions
    # @option options [Boolean] :validate Validate input, if a string or readable object.
    # @yield [api]
    # @yieldparam [API]
    # @raise [JsonLdError]
    def initialize(input, context, options = {}, &block)
      @options = {compactArrays: true, rename_bnodes: true}.merge(options)
      @options[:validate] = true if @options[:processingMode] == "json-ld-1.0"
      @options[:documentLoader] ||= self.class.method(:documentLoader)
      @namer = options[:unique_bnodes] ? BlankNodeUniqer.new : (@options[:rename_bnodes] ? BlankNodeNamer.new("b") : BlankNodeMapper.new)

      # For context via Link header
      context_ref = nil

      @value = case input
      when Array, Hash then input.dup
      when IO, StringIO
        @options = {base: input.base_uri}.merge(@options) if input.respond_to?(:base_uri)

        # if input impelements #links, attempt to get a contextUrl from that link
        content_type = input.respond_to?(:content_type) ? input.content_type : "application/json"
        context_ref = if content_type.start_with?('application/json') && input.respond_to?(:links)
          link = input.links.find_link(%w(rel http://www.w3.org/ns/json-ld#context))
          link.href if link
        end

        validate_input(input) if options[:validate]

        JSON.parse(input.read)
      when String
        remote_doc = @options[:documentLoader].call(input, @options)

        @options = {base: remote_doc.documentUrl}.merge(@options)
        context_ref = remote_doc.contextUrl

        case remote_doc.document
        when String
          validate_input(remote_doc.document) if options[:validate]
          JSON.parse(remote_doc.document)
        else
          remote_doc.document
        end
      end

      # Update calling context :base option, if not defined
      options[:base] ||= @options[:base] if @options[:base]

      # If not provided, first use context from document, or from a Link header
      context ||= (@value['@context'] if @value.is_a?(Hash)) || context_ref
      @context = Context.new(@options)
      @context = @context.parse(context) if context
      
      if block_given?
        case block.arity
          when 0, -1 then instance_eval(&block)
          else block.call(self)
        end
      end
    end
    
    ##
    # Expands the given input according to the steps in the Expansion Algorithm. The input must be copied, expanded and returned
    # if there are no errors. If the expansion fails, an appropriate exception must be thrown.
    #
    # The resulting `Array` either returned or yielded
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the expansion upon.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    # @raise [JsonLdError]
    # @yield jsonld
    # @yieldparam [Array<Hash>] jsonld
    #   The expanded JSON-LD document
    # @yieldreturn [Object] returned object
    # @return [Object, Array<Hash>]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the expanded JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#expansion-algorithm
    def self.expand(input, options = {})
      result = nil
      API.new(input, options[:expandContext], options) do |api|
        result = api.expand(api.value, nil, api.context)
      end

      # If, after the algorithm outlined above is run, the resulting element is an
      # JSON object with just a @graph property, element is set to the value of @graph's value.
      result = result['@graph'] if result.is_a?(Hash) && result.keys == %w(@graph)

      # Finally, if element is a JSON object, it is wrapped into an array.
      result = [result].compact unless result.is_a?(Array)
      block_given? ? yield(result) : result
    end

    ##
    # Compacts the given input according to the steps in the Compaction Algorithm. The input must be copied, compacted and
    # returned if there are no errors. If the compaction fails, an appropirate exception must be thrown.
    #
    # If no context is provided, the input document is compacted using the top-level context of the document
    #
    # The resulting `Hash` is either returned or yielded, if a block is given.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the compaction upon.
    # @param [String, #read, Hash, Array, JSON::LD::Context] context
    #   The base context to use when compacting the input.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Other options passed to {JSON::LD::API.expand}
    # @option options [Boolean] :expanded Input is already expanded
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The compacted JSON-LD document
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the compacted JSON-LD document
    # @raise [JsonLdError]
    # @see http://json-ld.org/spec/latest/json-ld-api/#compaction-algorithm
    def self.compact(input, context, options = {})
      expanded = result = nil

      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      expanded = options[:expanded] ? input : API.expand(input, options)

      API.new(expanded, context, options) do
        debug(".compact") {"expanded input: #{expanded.to_json(JSON_STATE) rescue 'malformed json'}"}
        result = compact(value, nil)

        # xxx) Add the given context to the output
        ctx = self.context.serialize
        if result.is_a?(Array)
          kwgraph = self.context.compact_iri('@graph', vocab: true, quiet: true)
          result = result.empty? ? {} : {kwgraph => result}
        end
        result = ctx.merge(result) unless ctx.empty?
      end
      block_given? ? yield(result) : result
    end

    ##
    # This algorithm flattens an expanded JSON-LD document by collecting all properties of a node in a single JSON object and labeling all blank nodes with blank node identifiers. This resulting uniform shape of the document, may drastically simplify the code required to process JSON-LD data in certain applications.
    #
    # The resulting `Array` is either returned, or yielded if a block is given.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object or array of JSON-LD objects to flatten or an IRI referencing the JSON-LD document to flatten.
    # @param [String, #read, Hash, Array, JSON::LD::EvaluationContext] context
    #   An optional external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Other options passed to {JSON::LD::API.expand}
    # @option options [Boolean] :expanded Input is already expanded
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The flattened JSON-LD document
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the flattened JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#framing-algorithm
    def self.flatten(input, context, options = {})
      flattened = []

      # Expand input to simplify processing
      expanded_input = options[:expanded] ? input : API.expand(input, options)

      # Initialize input using
      API.new(expanded_input, context, options) do
        debug(".flatten") {"expanded input: #{value.to_json(JSON_STATE) rescue 'malformed json'}"}

        # Initialize node map to a JSON object consisting of a single member whose key is @default and whose value is an empty JSON object.
        graphs = {'@default' => {}}
        create_node_map(value, graphs)

        default_graph = graphs['@default']
        graphs.keys.kw_sort.reject {|k| k == '@default'}.each do |graph_name|
          graph = graphs[graph_name]
          entry = default_graph[graph_name] ||= {'@id' => graph_name}
          nodes = entry['@graph'] ||= []
          graph.keys.kw_sort.each do |id|
            nodes << graph[id] unless node_reference?(graph[id])
          end
        end
        default_graph.keys.kw_sort.each do |id|
          flattened << default_graph[id] unless node_reference?(default_graph[id])
        end

        if context && !flattened.empty?
          # Otherwise, return the result of compacting flattened according the Compaction algorithm passing context ensuring that the compaction result uses the @graph keyword (or its alias) at the top-level, even if the context is empty or if there is only one element to put in the @graph array. This ensures that the returned document has a deterministic structure.
          compacted = depth {compact(flattened, nil)}
          compacted = [compacted] unless compacted.is_a?(Array)
          kwgraph = self.context.compact_iri('@graph', quiet: true)
          flattened = self.context.serialize.merge(kwgraph => compacted)
        end
      end

      block_given? ? yield(flattened) : flattened
    end

    ##
    # Frames the given input using the frame according to the steps in the Framing Algorithm. The input is used to build the
    # framed output and is returned if there are no errors. If there are no matches for the frame, null must be returned.
    # Exceptions must be thrown if there are errors.
    #
    # The resulting `Array` is either returned, or yielded if a block is given.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the framing on.
    # @param [String, #read, Hash, Array] frame
    #   The frame to use when re-arranging the data.
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Other options passed to {JSON::LD::API.expand}
    # @option options ['@last', '@always', '@never', '@link'] :embed ('@link')
    #   a flag specifying that objects should be directly embedded in the output,
    #   instead of being referred to by their IRI.
    # @option options [Boolean] :explicit (false)
    #   a flag specifying that for properties to be included in the output,
    #   they must be explicitly declared in the framing context.
    # @option options [Boolean] :requireAll (true)
    # @option options [Boolean] :omitDefault (false)
    #   a flag specifying that properties that are missing from the JSON-LD
    #   input should be omitted from the output.
    # @option options [Boolean] :expanded Input is already expanded
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The framed JSON-LD document
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the framed JSON-LD document
    # @raise [InvalidFrame]
    # @see http://json-ld.org/spec/latest/json-ld-api/#framing-algorithm
    def self.frame(input, frame, options = {})
      result = nil
      options = {
        base:           input.is_a?(String) ? input : '',
        compactArrays:  true,
        embed:          '@last',
        explicit:       false,
        requireAll:     true,
        omitDefault:    false,
        documentLoader: method(:documentLoader)
      }.merge(options)

      framing_state = {
        graphs:       {'@default' => {}, '@merged' => {}},
        subjectStack: [],
        link:         {},
      }

      # de-reference frame to create the framing object
      frame = case frame
      when Hash then frame.dup
      when IO, StringIO then JSON.parse(frame.read)
      when String
        remote_doc = options[:documentLoader].call(frame)
        case remote_doc.document
        when String then JSON.parse(remote_doc.document)
        else remote_doc.document
        end
      end

      # Expand input to simplify processing
      expanded_input = options[:expanded] ? input : API.expand(input, options)

      # Expand frame to simplify processing
      expanded_frame = API.expand(frame, options)

      # Initialize input using frame as context
      API.new(expanded_input, nil, options) do
        #debug(".frame") {"context from frame: #{context.inspect}"}
        debug(".frame") {"expanded frame: #{expanded_frame.to_json(JSON_STATE) rescue 'malformed json'}"}

        # Get framing nodes from expanded input, replacing Blank Node identifiers as necessary
        old_dbg, @options[:debug] = @options[:debug], nil
        create_node_map(value, framing_state[:graphs], '@merged')
        @options[:debug] = old_dbg
        framing_state[:subjects] = framing_state[:graphs]['@merged']
        debug(".frame") {"subjects: #{framing_state[:subjects].to_json(JSON_STATE) rescue 'malformed json'}"}

        result = []
        frame(framing_state, framing_state[:subjects].keys.sort, (expanded_frame.first || {}), options.merge(parent: result))
        debug(".frame") {"after frame: #{result.to_json(JSON_STATE) rescue 'malformed json'}"}
        
        # Initalize context from frame
        @context = depth {@context.parse(frame['@context'])}
        # Compact result
        compacted = depth {compact(result, nil)}
        compacted = [compacted] unless compacted.is_a?(Array)

        # Add the given context to the output
        kwgraph = context.compact_iri('@graph', quiet: true)
        result = context.serialize.merge({kwgraph => compacted})
        debug(".frame") {"after compact: #{result.to_json(JSON_STATE) rescue 'malformed json'}"}
        result = cleanup_preserve(result)
      end

      block_given? ? yield(result) : result
    end

    ##
    # Processes the input according to the RDF Conversion Algorithm, calling the provided callback for each triple generated.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to process when outputting statements.
    # @param [{Symbol,String => Object}] options
    #   See options in {JSON::LD::API#initialize}
    #   Options passed to {JSON::LD::API.expand}
    # @option options [Boolean] :produceGeneralizedRdf (false)
    #   If true, output will include statements having blank node predicates, otherwise they are dropped.
    # @option options [Boolean] :expanded Input is already expanded
    # @raise [JsonLdError]
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    # @return [RDF::Enumerable] set of statements, unless a block is given.
    def self.toRdf(input, options = {}, &block)
      unless block_given?
        results = []
        results.extend(RDF::Enumerable)
        self.toRdf(input, options) do |stmt|
          results << stmt
        end
        return results
      end

      # Expand input to simplify processing
      expanded_input = options[:expanded] ? input : API.expand(input, options.merge(ordered: false))

      API.new(expanded_input, nil, options) do
        # 1) Perform the Expansion Algorithm on the JSON-LD input.
        #    This removes any existing context to allow the given context to be cleanly applied.
        debug(".toRdf") {"expanded input: #{expanded_input.to_json(JSON_STATE) rescue 'malformed json'}"}

        # Generate _nodeMap_
        graphs = {'@default' => {}}
        create_node_map(expanded_input, graphs)
        debug(".toRdf") {"node map: #{graphs.to_json(JSON_STATE) rescue 'malformed json'}"}

        # Start generating statements
        graphs.each do |graph_name, graph|
          context = as_resource(graph_name) unless graph_name == '@default'
          debug(".toRdf") {"context: #{context ? context.to_ntriples : 'null'}"}
          # Drop results for graphs which are named with relative IRIs
          if graph_name.is_a?(RDF::URI) && !graph_name.absolute
            debug(".toRdf") {"drop relative graph_name: #{statement.to_ntriples}"}
            next
          end
          graph_to_rdf(graph) do |statement|
            next if statement.predicate.node? && !options[:produceGeneralizedRdf]
            # Drop results with relative IRIs
            relative = statement.to_a.any? do |r|
              case r
              when RDF::URI
                r.relative?
              when RDF::Literal
                r.has_datatype? && r.datatype.relative?
              else
                false
              end
            end
            if relative
              debug(".toRdf") {"drop statement with relative IRIs: #{statement.to_ntriples}"}
              next
            end

            statement.context = context if context
            if block_given?
              yield statement
            else
              results << statement
            end
          end
        end
      end
    end
    
    ##
    # Take an ordered list of RDF::Statements and turn them into a JSON-LD document.
    #
    # The resulting `Array` is either returned or yielded, if a block is given.
    #
    # @param [Array<RDF::Statement>] input
    # @param  [Hash{Symbol => Object}] options
    #   See options in {JSON::LD::API#initialize}
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The JSON-LD document in expanded form
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the expanded JSON-LD document
    def self.fromRdf(input, options = {}, &block)
      options = {useNativeTypes: false}.merge(options)
      result = nil

      API.new(nil, nil, options) do |api|
        result = api.from_statements(input)
      end

      block_given? ? yield(result) : result
    end

    ##
    # Default document loader.
    # @param [RDF::URI, String] url
    # @param [Hash<Symbol => Object>] options
    # @option options [Boolean] :validate
    #   Allow only appropriate content types
    # @yield remote_document
    # @yieldparam [RemoteDocument] remote_document
    # @yieldreturn [Object] returned object
    # @return [Object, RemoteDocument]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the retrieved remote document and context information unless block given
    # @raise [JsonLdError]
    def self.documentLoader(url, options = {})
      options = OPEN_OPTS.merge(options)
      RDF::Util::File.open_file(url, options) do |remote_doc|
        content_type = remote_doc.content_type if remote_doc.respond_to?(:content_type)
        # If the passed input is a DOMString representing the IRI of a remote document, dereference it. If the retrieved document's content type is neither application/json, nor application/ld+json, nor any other media type using a +json suffix as defined in [RFC6839], reject the promise passing an loading document failed error.
        if content_type && options[:validate]
          main, sub = content_type.split("/")
          raise JSON::LD::JsonLdError::LoadingDocumentFailed, "content_type: #{content_type}" if
            main != 'application' ||
            sub !~ /^(.*\+)?json$/
        end

        # If the input has been retrieved, the response has an HTTP Link Header [RFC5988] using the http://www.w3.org/ns/json-ld#context link relation and a content type of application/json or any media type with a +json suffix as defined in [RFC6839] except application/ld+json, update the active context using the Context Processing algorithm, passing the context referenced in the HTTP Link Header as local context. The HTTP Link Header is ignored for documents served as application/ld+json If multiple HTTP Link Headers using the http://www.w3.org/ns/json-ld#context link relation are found, the promise is rejected with a JsonLdError whose code is set to multiple context link headers and processing is terminated.
        contextUrl = unless content_type.nil? || content_type.start_with?("application/ld+json")
          # Get context link(s)
          # Note, we can't simply use #find_link, as we need to detect multiple
          links = remote_doc.links.links.select do |link|
            link.attr_pairs.include?(%w(rel http://www.w3.org/ns/json-ld#context))
          end
          raise JSON::LD::JsonLdError::MultipleContextLinkHeaders,
            "expected at most 1 Link header with rel=jsonld:context, got #{links.length}" if links.length > 1
          Array(links.first).first
        end

        doc_uri = remote_doc.base_uri rescue url
        doc = RemoteDocument.new(doc_uri, remote_doc.read, contextUrl)
        block_given? ? yield(doc) : doc
      end
    rescue IOError => e
      raise JSON::LD::JsonLdError::LoadingDocumentFailed, e.message
    end

    # Add class method aliases for backwards compatibility
    class << self
      alias :toRDF :toRdf
      alias :fromRDF :fromRdf
    end

    private
    def validate_input(input)
      return unless defined?(JsonLint)
      jsonlint = JsonLint::Linter.new
      unless jsonlint.respond_to?(:check_stream)
        warn "Skipping jsonlint, use latest version from GiHub until 0.1.1 released"
        return
      end
      input = StringIO.new(input) unless input.respond_to?(:read)
      unless jsonlint.check_stream(input)
        raise JsonLdError::LoadingDocumentFailed, jsonlint.errors[''].join("\n")
      end
      input.rewind
    end

    ##
    # A {RemoteDocument} is returned from a {documentLoader}.
    class RemoteDocument
      # @return [String] URL of the loaded document, after redirects
      attr_reader :documentUrl

      # @return [String, Array<Hash>, Hash]
      #   The retrieved document, either as raw text or parsed JSON
      attr_reader :document

      # @return [String]
      #   The URL of a remote context as specified by an HTTP Link header with rel=`http://www.w3.org/ns/json-ld#context`
      attr_accessor :contextUrl

      # @param [String] url URL of the loaded document, after redirects
      # @param [String, Array<Hash>, Hash] document
      #   The retrieved document, either as raw text or parsed JSON
      # @param [String] context_url (nil)
      #   The URL of a remote context as specified by an HTTP Link header with rel=`http://www.w3.org/ns/json-ld#context`
      def initialize(url, document, context_url = nil)
        @documentUrl = url
        @document = document
        @contextUrl = context_url
      end
    end
  end
end

