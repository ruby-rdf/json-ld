# -*- encoding: utf-8 -*-
# frozen_string_literal: true
require 'openssl'
require 'cgi'
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
  # @see https://www.w3.org/TR/json-ld11-api/#the-application-programming-interface
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class API
    include Expand
    include Compact
    include ToRDF
    include Flatten
    include FromRDF
    include Frame
    include RDF::Util::Logger

    # Options used for open_file
    OPEN_OPTS = {
      headers: {"Accept" => "application/ld+json, text/html;q=0.8, application/json;q=0.5"}
    }

    # The following constants are used to reduce object allocations
    LINK_REL_CONTEXT = %w(rel http://www.w3.org/ns/json-ld#context).freeze
    JSON_LD_PROCESSING_MODES = %w(json-ld-1.0 json-ld-1.1).freeze

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
    #   The Base IRI to use when expanding the document. This overrides the value of `input` if it is a _IRI_. If not specified and `input` is not an _IRI_, the base IRI defaults to the current document IRI if in a browser context, or the empty string if there is no document context. If not specified, and a base IRI is found from `input`, options[:base] will be modified with this value.
    # @option options [Boolean] :compactArrays (true)
    #   If set to `true`, the JSON-LD processor replaces arrays with just one element with that element during compaction. If set to `false`, all arrays will remain arrays even if they have just one element.
    # @option options [Boolean] :compactToRelative (true)
    #   Creates document relative IRIs when compacting, if `true`, otherwise leaves expanded.
    # @option options [Proc] :documentLoader
    #   The callback of the loader to be used to retrieve remote documents and contexts. If specified, it must be used to retrieve remote documents and contexts; otherwise, if not specified, the processor's built-in loader must be used. See {documentLoader} for the method signature.
    # @option options [String, #read, Hash, Array, JSON::LD::Context] :expandContext
    #   A context that is used to initialize the active context when expanding a document.
    # @option options [Boolean] :extractAllScripts
    #   If set, when given an HTML input without a fragment identifier, extracts all `script` elements with type `application/ld+json` into an array during expansion.
    # @option options [Boolean, String, RDF::URI] :flatten
    #   If set to a value that is not `false`, the JSON-LD processor must modify the output of the Compaction Algorithm or the Expansion Algorithm by coalescing all properties associated with each subject via the Flattening Algorithm. The value of `flatten must` be either an _IRI_ value representing the name of the graph to flatten, or `true`. If the value is `true`, then the first graph encountered in the input document is selected and flattened.
    # @option options [String] :language
    #   When set, this has the effect of inserting a context definition with `@language` set to the associated value, creating a default language for interpreting string values.
    # @option options [Symbol] :library
    #   One of :nokogiri or :rexml. If nil/unspecified uses :nokogiri if available, :rexml otherwise.
    # @option options [String] :processingMode
    #   Processing mode, json-ld-1.0 or json-ld-1.1.
    #   If `processingMode` is not specified, a mode of `json-ld-1.0` or `json-ld-1.1` is set, the context used for `expansion` or `compaction`.
    # @option options [Boolean] :rename_bnodes (true)
    #   Rename bnodes as part of expansion, or keep them the same.
    # @option options [Boolean]  :unique_bnodes   (false)
    #   Use unique bnode identifiers, defaults to using the identifier which the node was originally initialized with (if any).
    # @option options [Symbol] :adapter used with MultiJson
    # @option options [Boolean] :validate Validate input, if a string or readable object.
    # @option options [Boolean] :ordered (true)
    #   Order traversal of dictionary members by key when performing algorithms.
    # @yield [api]
    # @yieldparam [API]
    # @raise [JsonLdError]
    def initialize(input, context, rename_bnodes: true, unique_bnodes: false, **options, &block)
      @options = {
        compactArrays:      true,
        ordered:            false,
        extractAllScripts:  false,
      }.merge(options)
      @namer = unique_bnodes ? BlankNodeUniqer.new : (rename_bnodes ? BlankNodeNamer.new("b") : BlankNodeMapper.new)

      # For context via Link header
      _, context_ref = nil, nil

      @value = case input
      when Array, Hash then input.dup
      when IO, StringIO, String
        remote_doc = self.class.loadRemoteDocument(input, **@options)

        context_ref = remote_doc.contextUrl
        @options[:base] = remote_doc.documentUrl if remote_doc.documentUrl && !@options[:no_default_base]

        case remote_doc.document
        when String
          MultiJson.load(remote_doc.document, options)
        else
          # Already parsed
          remote_doc.document
        end
      end

      # If not provided, first use context from document, or from a Link header
      context ||= context_ref || {}
      @context = Context.parse(context || {}, @options)

      # If not set explicitly, the context figures out the processing mode
      @options[:processingMode] ||= @context.processingMode || "json-ld-1.0"

      if block_given?
        case block.arity
          when 0, -1 then instance_eval(&block)
          else block.call(self)
        end
      end
    end

    # This is used internally only
    private :initialize
    
    ##
    # Expands the given input according to the steps in the Expansion Algorithm. The input must be copied, expanded and returned if there are no errors. If the expansion fails, an appropriate exception must be thrown.
    #
    # The resulting `Array` either returned or yielded
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the expansion upon.
    # @param  [Hash{Symbol => Object}] options
    # @option options (see #initialize)
    # @raise [JsonLdError]
    # @yield jsonld, base_iri
    # @yieldparam [Array<Hash>] jsonld
    #   The expanded JSON-LD document
    # @yieldparam [RDF::URI] base_iri
    #   The document base as determined during expansion
    # @yieldreturn [Object] returned object
    # @return [Object, Array<Hash>]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the expanded JSON-LD document
    # @see https://www.w3.org/TR/json-ld11-api/#expansion-algorithm
    def self.expand(input, framing: false, **options, &block)
      result, doc_base = nil
      API.new(input, options[:expandContext], options) do
        result = self.expand(self.value, nil, self.context,
          ordered: @options[:ordered],
          framing: framing)
        doc_base = @options[:base]
      end

      # If, after the algorithm outlined above is run, the resulting element is an JSON object with just a @graph property, element is set to the value of @graph's value.
      result = result['@graph'] if result.is_a?(Hash) && result.length == 1 && result.key?('@graph')

      # Finally, if element is a JSON object, it is wrapped into an array.
      result = [result].compact unless result.is_a?(Array)

      if block_given?
        case block.arity
        when 1 then yield(result)
        when 2 then yield(result, doc_base)
        else
          raise "Unexpected number of yield parameters to expand"
        end
      else
        result
      end
    end

    ##
    # Compacts the given input according to the steps in the Compaction Algorithm. The input must be copied, compacted and returned if there are no errors. If the compaction fails, an appropirate exception must be thrown.
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
    # @option options (see #initialize)
    # @option options [Boolean] :expanded Input is already expanded
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The compacted JSON-LD document
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the compacted JSON-LD document
    # @raise [JsonLdError]
    # @see https://www.w3.org/TR/json-ld11-api/#compaction-algorithm
    def self.compact(input, context, expanded: false, **options)
      result = nil
      options = {compactToRelative:  true}.merge(options)

      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      expanded_input = expanded ? input : API.expand(input, options.merge(ordered: false)) do |res, base_iri|
        options[:base] ||= base_iri if options[:compactToRelative]
        res
      end

      API.new(expanded_input, context, no_default_base: true, **options) do
        log_debug(".compact") {"expanded input: #{expanded_input.to_json(JSON_STATE) rescue 'malformed json'}"}
        result = compact(value, ordered: @options[:ordered])

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
    # @option options (see #initialize)
    # @option options [Boolean] :expanded Input is already expanded
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The flattened JSON-LD document
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the flattened JSON-LD document
    # @see https://www.w3.org/TR/json-ld11-api/#framing-algorithm
    def self.flatten(input, context, expanded: false, **options)
      flattened = []
      options = {
        compactToRelative:  true,
        extractAllScripts:  true,
      }.merge(options)

      # Expand input to simplify processing
      expanded_input = expanded ? input : API.expand(input, options) do |result, base_iri|
        options[:base] ||= base_iri if options[:compactToRelative]
        result
      end

      # Initialize input using
      API.new(expanded_input, context, no_default_base: true, **options) do
        log_debug(".flatten") {"expanded input: #{value.to_json(JSON_STATE) rescue 'malformed json'}"}

        # Initialize node map to a JSON object consisting of a single member whose key is @default and whose value is an empty JSON object.
        graph_maps = {'@default' => {}}
        create_node_map(value, graph_maps)

        default_graph = graph_maps['@default']
        graph_maps.keys.opt_sort(ordered: @options[:ordered]).each do |graph_name|
          next if graph_name == '@default'

          graph = graph_maps[graph_name]
          entry = default_graph[graph_name] ||= {'@id' => graph_name}
          nodes = entry['@graph'] ||= []
          graph.keys.opt_sort(ordered: @options[:ordered]).each do |id|
            nodes << graph[id] unless node_reference?(graph[id])
          end
        end
        default_graph.keys.opt_sort(ordered: @options[:ordered]).each do |id|
          flattened << default_graph[id] unless node_reference?(default_graph[id])
        end

        if context && !flattened.empty?
          # Otherwise, return the result of compacting flattened according the Compaction algorithm passing context ensuring that the compaction result uses the @graph keyword (or its alias) at the top-level, even if the context is empty or if there is only one element to put in the @graph array. This ensures that the returned document has a deterministic structure.
          compacted = as_array(compact(flattened, ordered: @options[:ordered]))
          kwgraph = self.context.compact_iri('@graph', quiet: true)
          flattened = self.context.serialize.merge(kwgraph => compacted)
        end
      end

      block_given? ? yield(flattened) : flattened
    end

    ##
    # Frames the given input using the frame according to the steps in the Framing Algorithm. The input is used to build the framed output and is returned if there are no errors. If there are no matches for the frame, null must be returned. Exceptions must be thrown if there are errors.
    #
    # The resulting `Array` is either returned, or yielded if a block is given.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to copy and perform the framing on.
    # @param [String, #read, Hash, Array] frame
    #   The frame to use when re-arranging the data.
    # @option options (see #initialize)
    # @option options ['@always', '@first', '@last', '@link', '@once', '@never'] :embed ('@last')
    #   a flag specifying that objects should be directly embedded in the output, instead of being referred to by their IRI.
    # @option options [Boolean] :explicit (false)
    #   a flag specifying that for properties to be included in the output, they must be explicitly declared in the framing context.
    # @option options [Boolean] :requireAll (true)
    #   A flag specifying that all properties present in the input frame must either have a default value or be present in the JSON-LD input for the frame to match.
    # @option options [Boolean] :omitDefault (false)
    #   a flag specifying that properties that are missing from the JSON-LD input should be omitted from the output.
    # @option options [Boolean] :expanded Input is already expanded
    # @option options [Boolean] :omitGraph does not use `@graph` at top level unless necessary to describe multiple objects, defaults to `true` if processingMode is 1.1, otherwise `false`.
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The framed JSON-LD document
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the framed JSON-LD document
    # @raise [InvalidFrame]
    # @see https://www.w3.org/TR/json-ld11-api/#framing-algorithm
    def self.frame(input, frame, expanded: false, **options)
      result = nil
      options = {
        base:                       (input if input.is_a?(String)),
        compactArrays:              true,
        compactToRelative:          true,
        embed:                      '@once',
        explicit:                   false,
        requireAll:                 false,
        omitDefault:                false,
      }.merge(options)

      framing_state = {
        graphMap:     {},
        graphStack:   [],
        subjectStack: [],
        link:         {},
      }

      # de-reference frame to create the framing object
      frame = case frame
      when Hash then frame.dup
      when IO, StringIO, String
        remote_doc = loadRemoteDocument(frame,
                                        profile: 'http://www.w3.org/ns/json-ld#frame',
                                        requestProfile: 'http://www.w3.org/ns/json-ld#frame',
                                        **options)
        if remote_doc.document.is_a?(String)
          MultiJson.load(remote_doc.document)
        else
          remote_doc.document
        end
      end

      # Expand input to simplify processing
      expanded_input = expanded ? input : API.expand(input, options.merge(ordered: false)) do |res, base_iri|
        options[:base] ||= base_iri if options[:compactToRelative]
        res
      end

      # Expand frame to simplify processing
      expanded_frame = API.expand(frame, options.merge(framing: true, ordered: false))

      # Initialize input using frame as context
      API.new(expanded_input, frame['@context'], no_default_base: true, **options) do
        log_debug(".frame") {"expanded input: #{expanded_input.to_json(JSON_STATE) rescue 'malformed json'}"}
        log_debug(".frame") {"expanded frame: #{expanded_frame.to_json(JSON_STATE) rescue 'malformed json'}"}

        if context.processingMode == 'json-ld-1.1' && %w(@first @last).include?(options[:embed])
          raise JSON::LD::JsonLdError::InvalidEmbedValue, "#{options[:embed]} is not a valid value of @embed in 1.1 mode" if @options[:validate]
          warn "[DEPRECATION] #{options[:embed]}  is not a valid value of @embed in 1.1 mode.\n"
        end

        # Set omitGraph option, if not present, based on processingMode
        unless options.has_key?(:omitGraph)
          options[:omitGraph] = @options[:processingMode] != 'json-ld-1.0'
        end

        # Get framing nodes from expanded input, replacing Blank Node identifiers as necessary
        create_node_map(value, framing_state[:graphMap], active_graph: '@default')

        frame_keys = frame.keys.map {|k| context.expand_iri(k, vocab: true, quiet: true)}
        if frame_keys.include?('@graph')
          # If frame contains @graph, it matches the default graph.
          framing_state[:graph] = '@default'
        else
          # If frame does not contain @graph used the merged graph.
          framing_state[:graph] = '@merged'
          framing_state[:link]['@merged'] = {}
          framing_state[:graphMap]['@merged'] = merge_node_map_graphs(framing_state[:graphMap])
        end

        framing_state[:subjects] = framing_state[:graphMap][framing_state[:graph]]

        result = []
        frame(framing_state, framing_state[:subjects].keys.opt_sort(ordered: @options[:ordered]), (expanded_frame.first || {}), parent: result, **options)

        # Count blank node identifiers used in the document, if pruning
        unless @options[:processingMode] == 'json-ld-1.0'
          bnodes_to_clear = count_blank_node_identifiers(result).collect {|k, v| k if v == 1}.compact
          result = prune_bnodes(result, bnodes_to_clear)
        end

        # Initalize context from frame
        @context = @context.parse(frame['@context'])
        # Compact result
        compacted = compact(result, ordered: @options[:ordered])
        compacted = [compacted] unless options[:omitGraph] || compacted.is_a?(Array)

        # Add the given context to the output
        result = if !compacted.is_a?(Array)
          context.serialize.merge(compacted)
        else
          kwgraph = context.compact_iri('@graph', quiet: true)
          context.serialize.merge({kwgraph => compacted})
        end
        log_debug(".frame") {"after compact: #{result.to_json(JSON_STATE) rescue 'malformed json'}"}
        result = cleanup_preserve(result)
      end

      block_given? ? yield(result) : result
    end

    ##
    # Processes the input according to the RDF Conversion Algorithm, calling the provided callback for each triple generated.
    #
    # @param [String, #read, Hash, Array] input
    #   The JSON-LD object to process when outputting statements.
    # @option options (see #initialize)
    # @option options [Boolean] :produceGeneralizedRdf (false)
    #   If true, output will include statements having blank node predicates, otherwise they are dropped.
    # @option options [Boolean] :expanded Input is already expanded
    # @raise [JsonLdError]
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    # @return [RDF::Enumerable] set of statements, unless a block is given.
    def self.toRdf(input, expanded: false, **options, &block)
      unless block_given?
        results = []
        results.extend(RDF::Enumerable)
        self.toRdf(input, options) do |stmt|
          results << stmt
        end
        return results
      end

      options = {
        extractAllScripts:  true,
      }.merge(options)

      # Expand input to simplify processing
      expanded_input = expanded ? input : API.expand(input, options.merge(ordered: false))

      API.new(expanded_input, nil, options) do
        # 1) Perform the Expansion Algorithm on the JSON-LD input.
        #    This removes any existing context to allow the given context to be cleanly applied.
        log_debug(".toRdf") {"expanded input: #{expanded_input.to_json(JSON_STATE) rescue 'malformed json'}"}

        # Recurse through input
        expanded_input.each do |node|
          item_to_rdf(node) do |statement|
            next if statement.predicate.node? && !options[:produceGeneralizedRdf]

            # Drop invalid statements (other than IRIs)
            unless statement.valid_extended?
              log_debug(".toRdf") {"drop invalid statement: #{statement.to_nquads}"}
              next
            end

            yield statement
          end
        end
      end
    end
    
    ##
    # Take an ordered list of RDF::Statements and turn them into a JSON-LD document.
    #
    # The resulting `Array` is either returned or yielded, if a block is given.
    #
    # @param [RDF::Enumerable] input
    # @param  [Hash{Symbol => Object}] options
    # @option options (see #initialize)
    # @option options [Boolean] :useRdfType (false)
    #   If set to `true`, the JSON-LD processor will treat `rdf:type` like a normal property instead of using `@type`.
    # @option options [Boolean] :useNativeTypes (false) use native representations
    # @yield jsonld
    # @yieldparam [Hash] jsonld
    #   The JSON-LD document in expanded form
    # @yieldreturn [Object] returned object
    # @return [Object, Hash]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the expanded JSON-LD document
    def self.fromRdf(input, useRdfType: false, useNativeTypes: false, **options, &block)
      result = nil

      API.new(nil, nil, options) do
        result = from_statements(input,
          useRdfType: useRdfType,
          useNativeTypes: useNativeTypes,
          ordered: @options[:ordered])
      end

      block_given? ? yield(result) : result
    end

    ##
    # Uses built-in or provided documentLoader to retrieve a parsed document.
    #
    # @param [RDF::URI, String] url
    # @param [Boolean] extractAllScripts
    #   If set to `true`, when extracting JSON-LD script elements from HTML, unless a specific fragment identifier is targeted, extracts all encountered JSON-LD script elements using an array form, if necessary.
    # @param [String] profile
    #   When the resulting `contentType` is `text/html`, this option determines the profile to use for selecting a JSON-LD script elements.
    # @param [String] requestProfile
    #   One or more IRIs to use in the request as a profile parameter.
    # @param [Boolean] validate
    #   Allow only appropriate content types
    # @param [String, RDF::URI] base
    #   Location to use as documentUrl instead of `url`.
    # @param [Hash<Symbol => Object>] options
    # @yield remote_document
    # @yieldparam [RemoteDocumentRemoteDocument, RDF::Util::File::RemoteDocument] remote_document
    # @yieldreturn [Object] returned object
    # @return [Object, RemoteDocument]
    #   If a block is given, the result of evaluating the block is returned, otherwise, the retrieved remote document and context information unless block given
    # @raise [JsonLdError]
    def self.loadRemoteDocument(url,
                                extractAllScripts: false,
                                profile: nil,
                                requestProfile: nil,
                                validate: false,
                                base: nil,
                                **options)
      documentLoader = options.fetch(:documentLoader, self.method(:documentLoader))
      options = OPEN_OPTS.merge(options)
      if requestProfile
        # Add any request profile
        options[:headers]['Accept'] = options[:headers]['Accept'].sub('application/ld+json,', "application/ld+json;profile=#{requestProfile}, application/ld+json;q=0.9,")
      end
      documentLoader.call(url, **options) do |remote_doc|
        case remote_doc
        when RDF::Util::File::RemoteDocument
          # Convert to RemoteDocument
          context_url = if remote_doc.content_type != 'application/ld+json' &&
                           (remote_doc.content_type == 'application/json' ||
                            remote_doc.content_type.to_s.match?(%r(application/\w+\+json)))
            # Get context link(s)
            # Note, we can't simply use #find_link, as we need to detect multiple
            links = remote_doc.links.links.select do |link|
              link.attr_pairs.include?(LINK_REL_CONTEXT)
            end
            raise JSON::LD::JsonLdError::MultipleContextLinkHeaders,
              "expected at most 1 Link header with rel=jsonld:context, got #{links.length}" if links.length > 1
            Array(links.first).first
          end

          remote_doc = RemoteDocument.new(remote_doc.read,
            documentUrl: remote_doc.base_uri,
            contentType: remote_doc.content_type,
            contextUrl: context_url)
        when RemoteDocument
          # Pass through
        else
          raise JSON::LD::JsonLdError::LoadingDocumentFailed, "unknown result from documentLoader: #{remote_doc.class}"
        end

        # Use specified document location
        remote_doc.documentUrl = base if base

        # Parse any HTML
        if remote_doc.document.is_a?(String)
          remote_doc.document = case remote_doc.contentType
          when 'text/html'
            load_html(remote_doc.document,
                      url: remote_doc.documentUrl,
                      extractAllScripts: extractAllScripts,
                      profile: profile,
                      **options) do |base|
              remote_doc.documentUrl = base
            end
          else
            validate_input(remote_doc.document, url: remote_doc.documentUrl) if validate
            MultiJson.load(remote_doc.document, options)
          end
        end

        if remote_doc.contentType && validate
          raise IOError, "url: #{url}, contentType: #{remote_doc.contentType}" unless
            remote_doc.contentType.match?(/application\/(.+\+)?json|text\/html/)
        end
        block_given? ? yield(remote_doc) : remote_doc
      end
    rescue IOError => e
      raise JSON::LD::JsonLdError::LoadingDocumentFailed, e.message
    end

    ##
    # Default document loader.
    # @param [RDF::URI, String] url
    # @param [Boolean] extractAllScripts
    #   If set to `true`, when extracting JSON-LD script elements from HTML, unless a specific fragment identifier is targeted, extracts all encountered JSON-LD script elements using an array form, if necessary.
    # @param [String] profile
    #   When the resulting `contentType` is `text/html`, this option determines the profile to use for selecting a JSON-LD script elements.
    # @param [String] requestProfile
    #   One or more IRIs to use in the request as a profile parameter.
    # @param [Hash<Symbol => Object>] options
    # @yield remote_document
    # @yieldparam [RemoteDocument, RDF::Util::File::RemoteDocument] remote_document
    # @raise [IOError]
    def self.documentLoader(url, extractAllScripts: false, profile: nil, requestProfile: nil, **options, &block)
      case url
      when IO, StringIO
        base_uri = options[:base]
        base_uri ||= url.base_uri if url.respond_to?(:base_uri)
        content_type = options[:content_type]
        content_type ||= url.content_type if url.respond_to?(:content_type)
        context_url = if url.respond_to?(:links) && url.links
         (content_type == 'appliaction/json' || content_type.match?(%r(application/(^ld)+json)))
          link = url.links.find_link(LINK_REL_CONTEXT)
          link.href if link
        end

        block.call(RemoteDocument.new(url.read,
          documentUrl: base_uri,
          contentType: content_type,
          contextUrl: context_url))
      else
        RDF::Util::File.open_file(url, options, &block)
      end
    end

    # Add class method aliases for backwards compatibility
    class << self
      alias :toRDF :toRdf
      alias :fromRDF :fromRdf
    end

    ##
    # Load one or more script tags from an HTML source.
    # Unescapes and uncomments input, returns the internal representation
    # Yields document base
    # @param [String] input
    # @param [String] url   Original URL
    # @param [:nokogiri, :rexml] library (nil)
    # @param [Boolean] extractAllScripts (false)
    # @param [Boolean] profile (nil) Optional priortized profile when loading a single script by type.
    # @param [Hash{Symbol => Object}] options
    def self.load_html(input, url:,
                         library: nil,
                         extractAllScripts: false,
                         profile: nil,
                         **options)

      if input.is_a?(String)
        library ||= begin
          require 'nokogiri'
          :nokogiri
        rescue LoadError
          :rexml
        end
        require "json/ld/html/#{library}"

        # Parse HTML using the appropriate library
        @implementation = case library
        when :nokogiri then Nokogiri
        when :rexml then REXML
        end
        self.extend(@implementation)

        input = begin
          initialize_html(input, options)
        rescue
          raise JSON::LD::JsonLdError::LoadingDocumentFailed, "Malformed HTML document: #{$!.message}"
        end

        # Potentially update options[:base]
        if html_base = input.at_xpath("/html/head/base/@href")
          base = RDF::URI(url) if url
          html_base = RDF::URI(html_base)
          html_base = base.join(html_base) if base
          yield html_base
        end
      end

      url = RDF::URI.parse(url)
      if url.fragment
        id = CGI.unescape(url.fragment)
        # Find script with an ID based on that fragment.
        element = input.at_xpath("//script[@id='#{id}']")
        raise JSON::LD::JsonLdError::InvalidScriptElement, "No script tag found with id=#{id}" unless element
        raise JSON::LD::JsonLdError::InvalidScriptElement, "Script tag has type=#{element.attributes['type']}" unless element.attributes['type'].to_s.start_with?('application/ld+json')
        content = element.inner_html
        validate_input(content, url: url) if options[:validate]
        MultiJson.load(content, options)
      elsif extractAllScripts
        res = []
        elements = if profile
          es = input.xpath("//script[starts-with(@type, 'application/ld+json;profile=#{profile}')]")
          # If no profile script, just take a single script without profile
          es = [input.at_xpath("//script[starts-with(@type, 'application/ld+json')]")] if es.empty?
          es
        else
          input.xpath("//script[starts-with(@type, 'application/ld+json')]")
        end
        elements.each do |element|
          content = element.inner_html
          validate_input(content, url: url) if options[:validate]
          r = MultiJson.load(content, options)
          if r.is_a?(Hash)
            res << r
          elsif r.is_a?(Array)
            res = res.concat(r)
          end
        end
        res
      else
        # Find the first script with type application/ld+json.
        element = input.at_xpath("//script[starts-with(@type, 'application/ld+json;profile=#{profile}')]") if profile
        element ||= input.at_xpath("//script[starts-with(@type, 'application/ld+json')]")
        content = element ? element.inner_html : "[]"
        validate_input(content, url: url) if options[:validate]
        MultiJson.load(content, options)
      end
    rescue JSON::LD::JsonLdError::LoadingDocumentFailed, MultiJson::ParseError => e
      raise JSON::LD::JsonLdError::InvalidScriptElement, e.message
    end

    ##
    # Validate JSON using JsonLint, if loaded
    private
    def self.validate_input(input, url:)
      return unless defined?(JsonLint)
      jsonlint = JsonLint::Linter.new
      input = StringIO.new(input) unless input.respond_to?(:read)
      unless jsonlint.check_stream(input)
        raise JsonLdError::LoadingDocumentFailed, "url: #{url}\n" + jsonlint.errors[''].join("\n")
      end
      input.rewind
    end

    ##
    # A {RemoteDocument} is returned from a {documentLoader}.
    class RemoteDocument
      # The final URL of the loaded document. This is important to handle HTTP redirects properly.
      # @return [String]
      attr_accessor :documentUrl

      # The Content-Type of the loaded document, exclusive of any optional parameters.
      # @return [String]
      attr_reader :contentType

      # @return [String]
      #   The URL of a remote context as specified by an HTTP Link header with rel=`http://www.w3.org/ns/json-ld#context`
      attr_accessor :contextUrl

      # The parsed retrieved document.
      # @return [Array<Hash>, Hash]
      attr_accessor :document

      # The value of any profile parameter retrieved as part of the original contentType.
      # @return [String]
      attr_accessor :profile

      # @param [RDF::Util::File::RemoteDocument] remote_doc
      # @option options [Hash{Symbol => Object}] options
      def initialize(document, documentUrl: nil, contentType: nil, contextUrl: nil, profile: nil, **options)
        @document = document
        @documentUrl = documentUrl || options[:base_uri]
        @contentType = contentType || options[:content_type]
        @contextUrl = contextUrl
        @profile = profile
      end
    end
  end
end

