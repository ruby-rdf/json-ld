# frozen_string_literal: true

require 'English'

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

module JSON
  module LD
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
        headers: { "Accept" => "application/ld+json, text/html;q=0.8, application/xhtml+xml;q=0.8, application/json;q=0.5" }
      }

      # The following constants are used to reduce object allocations
      LINK_REL_CONTEXT = %w[rel http://www.w3.org/ns/json-ld#context].freeze
      LINK_REL_ALTERNATE = %w[rel alternate].freeze
      LINK_TYPE_JSONLD = %w[type application/ld+json].freeze
      JSON_LD_PROCESSING_MODES = %w[json-ld-1.0 json-ld-1.1].freeze

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
      # @option options [Symbol] :adapter used with MultiJson
      # @option options [RDF::URI, String, #to_s] :base
      #   The Base IRI to use when expanding the document. This overrides the value of `input` if it is a _IRI_. If not specified and `input` is not an _IRI_, the base IRI defaults to the current document IRI if in a browser context, or the empty string if there is no document context. If not specified, and a base IRI is found from `input`, options[:base] will be modified with this value.
      # @option options [Boolean] :compactArrays (true)
      #   If set to `true`, the JSON-LD processor replaces arrays with just one element with that element during compaction. If set to `false`, all arrays will remain arrays even if they have just one element.
      # @option options [Boolean] :compactToRelative (true)
      #   Creates document relative IRIs when compacting, if `true`, otherwise leaves expanded.
      # @option options [Proc] :documentLoader
      #   The callback of the loader to be used to retrieve remote documents and contexts. If specified, it must be used to retrieve remote documents and contexts; otherwise, if not specified, the processor's built-in loader must be used. See {documentLoader} for the method signature.
      # @option options [String, #read, Hash, Array, JSON::LD::Context] :expandContext
      #   A context that is used to initialize the active context when expanding a document.
      # @option options [Boolean] :extendedRepresentation (false)
      #   Use the extended internal representation.
      # @option options [Boolean] :extractAllScripts
      #   If set, when given an HTML input without a fragment identifier, extracts all `script` elements with type `application/ld+json` into an array during expansion.
      # @option options [Boolean, String, RDF::URI] :flatten
      #   If set to a value that is not `false`, the JSON-LD processor must modify the output of the Compaction Algorithm or the Expansion Algorithm by coalescing all properties associated with each subject via the Flattening Algorithm. The value of `flatten must` be either an _IRI_ value representing the name of the graph to flatten, or `true`. If the value is `true`, then the first graph encountered in the input document is selected and flattened.
      # @option options [String] :language
      #   When set, this has the effect of inserting a context definition with `@language` set to the associated value, creating a default language for interpreting string values.
      # @option options [Symbol] :library
      #   One of :nokogiri or :rexml. If nil/unspecified uses :nokogiri if available, :rexml otherwise.
      # @option options [Boolean] :lowercaseLanguage
      #   By default, language tags are left as is. To normalize to lowercase, set this option to `true`.
      # @option options [Boolean] :ordered (true)
      #   Order traversal of dictionary members by key when performing algorithms.
      # @option options [String] :processingMode
      #   Processing mode, json-ld-1.0 or json-ld-1.1.
      # @option options [Boolean] :rdfstar      (false)
      #   support parsing JSON-LD-star statement resources.
      # @option options [Boolean] :rename_bnodes (true)
      #   Rename bnodes as part of expansion, or keep them the same.
      # @option options [Boolean]  :unique_bnodes   (false)
      #   Use unique bnode identifiers, defaults to using the identifier which the node was originally initialized with (if any).
      # @option options [Boolean] :validate Validate input, if a string or readable object.
      # @yield [api]
      # @yieldparam [API]
      # @raise [JsonLdError]
      def initialize(input, context, **options, &block)
        @options = {
          compactArrays: true,
          ordered: false,
          extractAllScripts: false,
          rename_bnodes: true,
          unique_bnodes: false
        }.merge(options)
        @namer = if @options[:unique_bnodes]
          BlankNodeUniqer.new
        else
          (@options[:rename_bnodes] ? BlankNodeNamer.new("b") : BlankNodeMapper.new)
        end

        @options[:base] = RDF::URI(@options[:base]) if @options[:base] && !@options[:base].is_a?(RDF::URI)
        # For context via Link header
        _ = nil
        context_ref = nil

        @value = case input
        when Array, Hash then input.dup
        when IO, StringIO, String
          remote_doc = self.class.loadRemoteDocument(input, **@options)

          context_ref = remote_doc.contextUrl
          @options[:base] = RDF::URI(remote_doc.documentUrl) if remote_doc.documentUrl && !@options[:no_default_base]

          case remote_doc.document
          when String
            mj_opts = options.keep_if { |k, v| k != :adapter || MUTLI_JSON_ADAPTERS.include?(v) }
            MultiJson.load(remote_doc.document, **mj_opts)
          else
            # Already parsed
            remote_doc.document
          end
        end

        # If not provided, first use context from document, or from a Link header
        context ||= context_ref || {}
        @context = Context.parse(context, **@options)

        return unless block

        case block.arity
        when 0, -1 then instance_eval(&block)
        else yield(self)
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
      # @param [Proc] serializer (nil)
      #   A Serializer method used for generating the JSON serialization of the result. If absent, the internal Ruby objects are returned, which can be transformed to JSON externally via `#to_json`.
      #   See {JSON::LD::API.serializer}.
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
      def self.expand(input, framing: false, serializer: nil, **options, &block)
        result = doc_base = nil
        API.new(input, options[:expandContext], **options) do
          result = expand(value, nil, context,
            framing: framing)
          doc_base = @options[:base]
        end

        # If, after the algorithm outlined above is run, the resulting element is an JSON object with just a @graph property, element is set to the value of @graph's value.
        result = result['@graph'] if result.is_a?(Hash) && result.length == 1 && result.key?('@graph')

        # Finally, if element is a JSON object, it is wrapped into an array.
        result = [result].compact unless result.is_a?(Array)
        result = serializer.call(result, **options) if serializer

        if block
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
      # @param [Proc] serializer (nil)
      #   A Serializer instance used for generating the JSON serialization of the result. If absent, the internal Ruby objects are returned, which can be transformed to JSON externally via `#to_json`.
      #   See {JSON::LD::API.serializer}.
      # @param [Boolean] expanded (false) Input is already expanded
      # @param  [Hash{Symbol => Object}] options
      # @option options (see #initialize)
      # @yield jsonld
      # @yieldparam [Hash] jsonld
      #   The compacted JSON-LD document
      # @yieldreturn [Object] returned object
      # @return [Object, Hash]
      #   If a block is given, the result of evaluating the block is returned, otherwise, the compacted JSON-LD document
      # @raise [JsonLdError]
      # @see https://www.w3.org/TR/json-ld11-api/#compaction-algorithm
      def self.compact(input, context, expanded: false, serializer: nil, **options)
        result = nil
        options = { compactToRelative: true }.merge(options)

        # 1) Perform the Expansion Algorithm on the JSON-LD input.
        #    This removes any existing context to allow the given context to be cleanly applied.
        expanded_input = if expanded
          input
        else
          API.expand(input, ordered: false, **options) do |res, base_iri|
            options[:base] ||= RDF::URI(base_iri) if base_iri && options[:compactToRelative]
            res
          end
        end

        API.new(expanded_input, context, no_default_base: true, **options) do
          # log_debug(".compact") {"expanded input: #{expanded_input.to_json(JSON_STATE) rescue 'malformed json'}"}
          result = compact(value)

          # xxx) Add the given context to the output
          ctx = self.context.serialize(provided_context: context)
          if result.is_a?(Array)
            kwgraph = self.context.compact_iri('@graph', vocab: true)
            result = result.empty? ? {} : { kwgraph => result }
          end
          result = ctx.merge(result) unless ctx.fetch('@context', {}).empty?
        end
        result = serializer.call(result, **options) if serializer
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
      # @param [Boolean] expanded (false) Input is already expanded
      # @param [Proc] serializer (nil)
      #   A Serializer instance used for generating the JSON serialization of the result. If absent, the internal Ruby objects are returned, which can be transformed to JSON externally via `#to_json`.
      #   See {JSON::LD::API.serializer}.
      # @param  [Hash{Symbol => Object}] options
      # @option options (see #initialize)
      # @option options [Boolean] :createAnnotations
      #   Unfold embedded nodes which can be represented using `@annotation`.
      # @yield jsonld
      # @yieldparam [Hash] jsonld
      #   The flattened JSON-LD document
      # @yieldreturn [Object] returned object
      # @return [Object, Hash]
      #   If a block is given, the result of evaluating the block is returned, otherwise, the flattened JSON-LD document
      # @see https://www.w3.org/TR/json-ld11-api/#framing-algorithm
      def self.flatten(input, context, expanded: false, serializer: nil, **options)
        flattened = []
        options = {
          compactToRelative: true
        }.merge(options)

        # Expand input to simplify processing
        expanded_input = if expanded
          input
        else
          API.expand(input, **options) do |result, base_iri|
            options[:base] ||= RDF::URI(base_iri) if base_iri && options[:compactToRelative]
            result
          end
        end

        # Initialize input using
        API.new(expanded_input, context, no_default_base: true, **options) do
          # log_debug(".flatten") {"expanded input: #{value.to_json(JSON_STATE) rescue 'malformed json'}"}

          # Rename blank nodes recusively. Note that this does not create new blank node identifiers where none exist, which is performed in the node map generation algorithm.
          @value = rename_bnodes(@value) if @options[:rename_bnodes]

          # Initialize node map to a JSON object consisting of a single member whose key is @default and whose value is an empty JSON object.
          graph_maps = { '@default' => {} }
          create_node_map(value, graph_maps)

          # If create annotations flag is set, then update each node map in graph maps with the result of calling the create annotations algorithm.
          if options[:createAnnotations]
            graph_maps.each_value do |node_map|
              create_annotations(node_map)
            end
          end

          default_graph = graph_maps['@default']
          graph_maps.keys.opt_sort(ordered: @options[:ordered]).each do |graph_name|
            next if graph_name == '@default'

            graph = graph_maps[graph_name]
            entry = default_graph[graph_name] ||= { '@id' => graph_name }
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
            compacted = as_array(compact(flattened))
            kwgraph = self.context.compact_iri('@graph', vocab: true)
            flattened = self.context
              .serialize(provided_context: context)
              .merge(kwgraph => compacted)
          end
        end

        flattened = serializer.call(flattened, **options) if serializer
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
      # @param [Boolean] expanded (false) Input is already expanded
      # @option options (see #initialize)
      # @option options ['@always', '@link', '@once', '@never'] :embed ('@once')
      #   a flag specifying that objects should be directly embedded in the output, instead of being referred to by their IRI.
      # @option options [Boolean] :explicit (false)
      #   a flag specifying that for properties to be included in the output, they must be explicitly declared in the framing context.
      # @option options [Boolean] :requireAll (false)
      #   A flag specifying that all properties present in the input frame must either have a default value or be present in the JSON-LD input for the frame to match.
      # @option options [Boolean] :omitDefault (false)
      #   a flag specifying that properties that are missing from the JSON-LD input should be omitted from the output.
      # @option options [Boolean] :pruneBlankNodeIdentifiers (true) removes blank node identifiers that are only used once.
      # @option options [Boolean] :omitGraph does not use `@graph` at top level unless necessary to describe multiple objects, defaults to `true` if processingMode is 1.1, otherwise `false`.
      # @yield jsonld
      # @yieldparam [Hash] jsonld
      #   The framed JSON-LD document
      # @yieldreturn [Object] returned object
      # @return [Object, Hash]
      #   If a block is given, the result of evaluating the block is returned, otherwise, the framed JSON-LD document
      # @raise [InvalidFrame]
      # @see https://www.w3.org/TR/json-ld11-api/#framing-algorithm
      def self.frame(input, frame, expanded: false, serializer: nil, **options)
        result = nil
        options = {
          base: (RDF::URI(input) if input.is_a?(String)),
          compactArrays: true,
          compactToRelative: true,
          embed: '@once',
          explicit: false,
          requireAll: false,
          omitDefault: false
        }.merge(options)

        framing_state = {
          graphMap: {},
          graphStack: [],
          subjectStack: [],
          link: {},
          embedded: false # False at the top-level
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
            mj_opts = options.keep_if { |k, v| k != :adapter || MUTLI_JSON_ADAPTERS.include?(v) }
            MultiJson.load(remote_doc.document, **mj_opts)
          else
            remote_doc.document
          end
        end

        # Expand input to simplify processing
        expanded_input = if expanded
          input
        else
          API.expand(input, ordered: false, **options) do |res, base_iri|
            options[:base] ||= RDF::URI(base_iri) if base_iri && options[:compactToRelative]
            res
          end
        end

        # Expand frame to simplify processing
        expanded_frame = API.expand(frame, framing: true, ordered: false, **options)

        # Initialize input using frame as context
        API.new(expanded_input, frame['@context'], no_default_base: true, **options) do
          # log_debug(".frame") {"expanded input: #{expanded_input.to_json(JSON_STATE) rescue 'malformed json'}"}
          # log_debug(".frame") {"expanded frame: #{expanded_frame.to_json(JSON_STATE) rescue 'malformed json'}"}

          if %w[@first @last].include?(options[:embed]) && context.processingMode('json-ld-1.1')
            if @options[:validate]
              raise JSON::LD::JsonLdError::InvalidEmbedValue,
                "#{options[:embed]} is not a valid value of @embed in 1.1 mode"
            end

            warn "[DEPRECATION] #{options[:embed]}  is not a valid value of @embed in 1.1 mode.\n"
          end

          # Set omitGraph option, if not present, based on processingMode
          options[:omitGraph] = context.processingMode('json-ld-1.1') unless options.key?(:omitGraph)

          # Rename blank nodes recusively. Note that this does not create new blank node identifiers where none exist, which is performed in the node map generation algorithm.
          @value = rename_bnodes(@value)

          # Get framing nodes from expanded input, replacing Blank Node identifiers as necessary
          create_node_map(value, framing_state[:graphMap], active_graph: '@default')

          frame_keys = frame.keys.map { |k| context.expand_iri(k, vocab: true) }
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
          frame(framing_state, framing_state[:subjects].keys.opt_sort(ordered: @options[:ordered]),
            (expanded_frame.first || {}), parent: result, **options)

          # Default to based on processinMode
          unless options.key?(:pruneBlankNodeIdentifiers)
            options[:pruneBlankNodeIdentifiers] = context.processingMode('json-ld-1.1')
          end

          # Count blank node identifiers used in the document, if pruning
          if options[:pruneBlankNodeIdentifiers]
            bnodes_to_clear = count_blank_node_identifiers(result).collect { |k, v| k if v == 1 }.compact
            result = prune_bnodes(result, bnodes_to_clear)
          end

          # Replace values with `@preserve` with the content of its entry.
          result = cleanup_preserve(result)
          # log_debug(".frame") {"expanded result: #{result.to_json(JSON_STATE) rescue 'malformed json'}"}

          # Compact result
          compacted = compact(result)

          # @replace `@null` with nil, compacting arrays
          compacted = cleanup_null(compacted)
          compacted = [compacted] unless options[:omitGraph] || compacted.is_a?(Array)

          # Add the given context to the output
          result = if compacted.is_a?(Array)
            kwgraph = context.compact_iri('@graph', vocab: true)
            { kwgraph => compacted }
          else
            compacted
          end
          # Only add context if one was provided
          result = context.serialize(provided_context: frame).merge(result) if frame['@context']

          # log_debug(".frame") {"after compact: #{result.to_json(JSON_STATE) rescue 'malformed json'}"}
          result
        end

        result = serializer.call(result, **options) if serializer
        block_given? ? yield(result) : result
      end

      ##
      # Processes the input according to the RDF Conversion Algorithm, calling the provided callback for each triple generated.
      #
      # @param [String, #read, Hash, Array] input
      #   The JSON-LD object to process when outputting statements.
      # @param [Boolean] expanded (false) Input is already expanded
      # @option options (see #initialize)
      # @option options [Boolean] :produceGeneralizedRdf (false)
      #   If true, output will include statements having blank node predicates, otherwise they are dropped.
      # @option options [Boolean] :extractAllScripts (true)
      #   If set, when given an HTML input without a fragment identifier, extracts all `script` elements with type `application/ld+json` into an array during expansion.
      # @raise [JsonLdError]
      # @yield statement
      # @yieldparam [RDF::Statement] statement
      # @return [RDF::Enumerable] set of statements, unless a block is given.
      def self.toRdf(input, expanded: false, **options)
        unless block_given?
          results = []
          results.extend(RDF::Enumerable)
          toRdf(input, expanded: expanded, **options) do |stmt|
            results << stmt
          end
          return results
        end

        options = {
          extractAllScripts: true
        }.merge(options)

        # Flatten input to simplify processing
        flattened_input = API.flatten(input, nil, expanded: expanded, ordered: false, **options)

        API.new(flattened_input, nil, **options) do
          # 1) Perform the Expansion Algorithm on the JSON-LD input.
          #    This removes any existing context to allow the given context to be cleanly applied.
          # log_debug(".toRdf") {"flattened input: #{flattened_input.to_json(JSON_STATE) rescue 'malformed json'}"}

          # Recurse through input
          flattened_input.each do |node|
            item_to_rdf(node) do |statement|
              next if statement.predicate.node? && !options[:produceGeneralizedRdf]

              # Drop invalid statements (other than IRIs)
              unless statement.valid_extended?
                # log_debug(".toRdf") {"drop invalid statement: #{statement.to_nquads}"}
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
      # @param [Boolean] useRdfType (false)
      #   If set to `true`, the JSON-LD processor will treat `rdf:type` like a normal property instead of using `@type`.
      # @param [Boolean] useNativeTypes (false) use native representations
      # @param [Proc] serializer (nil)
      #   A Serializer instance used for generating the JSON serialization of the result. If absent, the internal Ruby objects are returned, which can be transformed to JSON externally via `#to_json`.
      #   See {JSON::LD::API.serializer}.
      # @param  [Hash{Symbol => Object}] options
      # @option options (see #initialize)
      # @yield jsonld
      # @yieldparam [Hash] jsonld
      #   The JSON-LD document in expanded form
      # @yieldreturn [Object] returned object
      # @return [Object, Hash]
      #   If a block is given, the result of evaluating the block is returned, otherwise, the expanded JSON-LD document
      def self.fromRdf(input, useRdfType: false, useNativeTypes: false, serializer: nil, **options)
        result = nil

        API.new(nil, nil, **options) do
          result = from_statements(input,
            extendedRepresentation: options[:extendedRepresentation],
            useRdfType: useRdfType,
            useNativeTypes: useNativeTypes)
        end

        result = serializer.call(result, **options) if serializer
        block_given? ? yield(result) : result
      end

      ##
      # Uses built-in or provided documentLoader to retrieve a parsed document.
      #
      # @param [RDF::URI, String] url
      # @param [Regexp] allowed_content_types
      #   A regular expression matching other content types allowed
      #   beyond types for JSON and HTML.
      # @param [String, RDF::URI] base
      #   Location to use as documentUrl instead of `url`.
      # @option options [Proc] :documentLoader
      #   The callback of the loader to be used to retrieve remote documents and contexts.
      # @param [Boolean] extractAllScripts
      #   If set to `true`, when extracting JSON-LD script elements from HTML, unless a specific fragment identifier is targeted, extracts all encountered JSON-LD script elements using an array form, if necessary.
      # @param [String] profile
      #   When the resulting `contentType` is `text/html` or `application/xhtml+xml`, this option determines the profile to use for selecting a JSON-LD script elements.
      # @param [String] requestProfile
      #   One or more IRIs to use in the request as a profile parameter.
      # @param [Boolean] validate (false)
      #   Allow only appropriate content types
      # @param [Hash<Symbol => Object>] options
      # @yield remote_document
      # @yieldparam [RemoteDocumentRemoteDocument, RDF::Util::File::RemoteDocument] remote_document
      # @yieldreturn [Object] returned object
      # @return [Object, RemoteDocument]
      #   If a block is given, the result of evaluating the block is returned, otherwise, the retrieved remote document and context information unless block given
      # @raise [JsonLdError]
      def self.loadRemoteDocument(url,
                                  allowed_content_types: nil,
                                  base: nil,
                                  documentLoader: nil,
                                  extractAllScripts: false,
                                  profile: nil,
                                  requestProfile: nil,
                                  validate: false,
                                  **options)
        documentLoader ||= method(:documentLoader)
        options = OPEN_OPTS.merge(options)
        if requestProfile
          # Add any request profile
          options[:headers]['Accept'] =
            options[:headers]['Accept'].sub('application/ld+json,',
              "application/ld+json;profile=#{requestProfile}, application/ld+json;q=0.9,")
        end
        documentLoader.call(url, extractAllScripts: extractAllScripts, **options) do |remote_doc|
          case remote_doc
          when RDF::Util::File::RemoteDocument
            # Convert to RemoteDocument
            context_url = if remote_doc.content_type != 'application/ld+json' &&
                             (remote_doc.content_type == 'application/json' ||
                              remote_doc.content_type.to_s.match?(%r{application/\w+\+json}))
              # Get context link(s)
              # Note, we can't simply use #find_link, as we need to detect multiple
              links = remote_doc.links.links.select do |link|
                link.attr_pairs.include?(LINK_REL_CONTEXT)
              end
              if links.length > 1
                raise JSON::LD::JsonLdError::MultipleContextLinkHeaders,
                  "expected at most 1 Link header with rel=jsonld:context, got #{links.length}"
              end
              Array(links.first).first
            end

            # If content-type is not application/ld+json, nor any other +json and a link with rel=alternate and type='application/ld+json' is found, use that instead
            alternate = !remote_doc.content_type.match?(%r{application/(\w*\+)?json}) && remote_doc.links.links.detect do |link|
              link.attr_pairs.include?(LINK_REL_ALTERNATE) &&
                link.attr_pairs.include?(LINK_TYPE_JSONLD)
            end

            remote_doc = if alternate
              # Load alternate relative to URL
              loadRemoteDocument(RDF::URI(url).join(alternate.href),
                extractAllScripts: extractAllScripts,
                profile: profile,
                requestProfile: requestProfile,
                validate: validate,
                base: base,
                  **options)
            else
              RemoteDocument.new(remote_doc.read,
                documentUrl: remote_doc.base_uri,
                contentType: remote_doc.content_type,
                contextUrl: context_url)
            end
          when RemoteDocument
            # Pass through
          else
            raise JSON::LD::JsonLdError::LoadingDocumentFailed,
              "unknown result from documentLoader: #{remote_doc.class}"
          end

          # Use specified document location
          remote_doc.documentUrl = base if base

          # Parse any HTML
          if remote_doc.document.is_a?(String)
            remote_doc.document = case remote_doc.contentType
            when 'text/html', 'application/xhtml+xml'
              load_html(remote_doc.document,
                url: remote_doc.documentUrl,
                extractAllScripts: extractAllScripts,
                profile: profile,
                        **options) do |base|
                remote_doc.documentUrl = base
              end
            else
              validate_input(remote_doc.document, url: remote_doc.documentUrl) if validate
              mj_opts = options.keep_if { |k, v| k != :adapter || MUTLI_JSON_ADAPTERS.include?(v) }
              MultiJson.load(remote_doc.document, **mj_opts)
            end
          end

          if remote_doc.contentType && validate && !(remote_doc.contentType.match?(%r{application/(.+\+)?json|text/html|application/xhtml\+xml}) ||
              (allowed_content_types && remote_doc.contentType.match?(allowed_content_types)))
            raise IOError, "url: #{url}, contentType: #{remote_doc.contentType}"
          end

          block_given? ? yield(remote_doc) : remote_doc
        end
      rescue IOError, MultiJson::ParseError => e
        raise JSON::LD::JsonLdError::LoadingDocumentFailed, e.message
      end

      ##
      # Default document loader.
      # @param [RDF::URI, String] url
      # @param [Boolean] extractAllScripts
      #   If set to `true`, when extracting JSON-LD script elements from HTML, unless a specific fragment identifier is targeted, extracts all encountered JSON-LD script elements using an array form, if necessary.
      # @param [String] profile
      #   When the resulting `contentType` is `text/html` or `application/xhtml+xml`, this option determines the profile to use for selecting a JSON-LD script elements.
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
          context_url = if url.respond_to?(:links) && url.links &&
                           (content_type == 'application/json' || content_type.match?(%r{application/(^ld)+json}))
            link = url.links.find_link(LINK_REL_CONTEXT)
            link&.href
          end

          yield(RemoteDocument.new(url.read,
            documentUrl: base_uri,
            contentType: content_type,
            contextUrl: context_url))
        else
          RDF::Util::File.open_file(url, **options, &block)
        end
      end

      # Add class method aliases for backwards compatibility
      class << self
        alias toRDF toRdf
        alias fromRDF fromRdf
      end

      ##
      # Hash of recognized script types and the loaders that decode them
      # into a hash or array of hashes.
      #
      # @return Hash{type, Proc}
      SCRIPT_LOADERS = {
        'application/ld+json' => ->(content, url:, **options) do
            validate_input(content, url: url) if options[:validate]
            mj_opts = options.keep_if { |k, v| k != :adapter || MUTLI_JSON_ADAPTERS.include?(v) }
            MultiJson.load(content, **mj_opts)
          end
      }

      ##
      # Adds a loader for some specific content type
      #
      # @param [String] type
      # @param [Proc] loader
      def self.add_script_loader(type, loader)
        SCRIPT_LOADERS[type] = loader
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
          implementation = case library
          when :nokogiri then Nokogiri
          when :rexml then REXML
          end
          extend(implementation)

          input = begin
            send("initialize_html_#{library}".to_sym, input, **options)
          rescue StandardError
            raise JSON::LD::JsonLdError::LoadingDocumentFailed, "Malformed HTML document: #{$ERROR_INFO.message}"
          end

          # Potentially update options[:base]
          if (html_base = input.at_xpath("/html/head/base/@href"))
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
          raise JSON::LD::JsonLdError::LoadingDocumentFailed, "No script tag found with id=#{id}" unless element

          script_type = SCRIPT_LOADERS.keys.detect {|type| element.attributes['type'].to_s.start_with?(type)}
          unless script_type
            raise JSON::LD::JsonLdError::LoadingDocumentFailed,
              "Script tag has type=#{element.attributes['type']}"
          end

          loader = SCRIPT_LOADERS[script_type]
          loader.call(element.inner_html, url: url, **options)
        elsif extractAllScripts
          res = []

          SCRIPT_LOADERS.each do |type, loader|
            elements = if profile
              es = input.xpath("//script[starts-with(@type, '#{type};profile=#{profile}')]")
              # If no profile script, just take a single script without profile
              es = [input.at_xpath("//script[starts-with(@type, '#{type}')]")].compact if es.empty?
              es
            else
              input.xpath("//script[starts-with(@type, '#{type}')]")
            end
            elements.each do |element|
              content = element.inner_html
              r = loader.call(content, url: url, extractAllScripts: true, **options)
              if r.is_a?(Hash)
                res << r
              elsif r.is_a?(Array)
                res.concat(r)
              end
            end
          end
          res
        else
          # Find the first script with a known type
          script_type, element = nil, nil
          SCRIPT_LOADERS.keys.each do |type|
            next if script_type # already found the type
            element = input.at_xpath("//script[starts-with(@type, '#{type};profile=#{profile}')]") if profile
            element ||= input.at_xpath("//script[starts-with(@type, '#{type}')]")
            script_type = type if element
          end
          unless script_type
            raise JSON::LD::JsonLdError::LoadingDocumentFailed, "No script tag found" unless element
          end

          content = element.inner_html
          SCRIPT_LOADERS[script_type].call(content, url: url, **options)
        end
      rescue MultiJson::ParseError => e
        raise JSON::LD::JsonLdError::InvalidScriptElement, e.message
      end

      ##
      # The default serializer for serialzing Ruby Objects to JSON.
      #
      # Defaults to `MultiJson.dump`
      #
      # @param [Object] object
      # @param [Array<Object>] args
      #   other arguments that may be passed for some specific implementation.
      # @param [Hash<Symbol, Object>] options
      #   options passed from the invoking context.
      # @option options [Object] :serializer_opts (JSON_STATE)
      def self.serializer(object, *_args, **options)
        serializer_opts = options.fetch(:serializer_opts, JSON_STATE)
        MultiJson.dump(object, serializer_opts)
      end

      ##
      # Validate JSON using JsonLint, if loaded

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

        # @param [RDF::Util::File::RemoteDocument] document
        # @param [String] documentUrl
        #   The final URL of the loaded document. This is important to handle HTTP redirects properly.
        # @param [String] contentType
        #   The Content-Type of the loaded document, exclusive of any optional parameters.
        # @param [String] contextUrl
        #   The URL of a remote context as specified by an HTTP Link header with rel=`http://www.w3.org/ns/json-ld#context`
        # @param [String] profile
        #   The value of any profile parameter retrieved as part of the original contentType.
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
end
