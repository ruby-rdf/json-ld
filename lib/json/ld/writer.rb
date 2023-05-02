# frozen_string_literal: true

require 'json/ld/streaming_writer'
require 'link_header'

module JSON
  module LD
    ##
    # A JSON-LD parser in Ruby.
    #
    # Note that the natural interface is to write a whole graph at a time.
    # Writing statements or Triples will create a graph to add them to
    # and then serialize the graph.
    #
    # @example Obtaining a JSON-LD writer class
    #   RDF::Writer.for(:jsonld)         #=> JSON::LD::Writer
    #   RDF::Writer.for("etc/test.json")
    #   RDF::Writer.for(:file_name      => "etc/test.json")
    #   RDF::Writer.for(file_extension: "json")
    #   RDF::Writer.for(:content_type   => "application/turtle")
    #
    # @example Serializing RDF graph into an JSON-LD file
    #   JSON::LD::Writer.open("etc/test.json") do |writer|
    #     writer << graph
    #   end
    #
    # @example Serializing RDF statements into an JSON-LD file
    #   JSON::LD::Writer.open("etc/test.json") do |writer|
    #     graph.each_statement do |statement|
    #       writer << statement
    #     end
    #   end
    #
    # @example Serializing RDF statements into an JSON-LD string
    #   JSON::LD::Writer.buffer do |writer|
    #     graph.each_statement do |statement|
    #       writer << statement
    #     end
    #   end
    #
    # The writer will add prefix definitions, and use them for creating @context definitions, and minting CURIEs
    #
    # @example Creating @@context prefix definitions in output
    #   JSON::LD::Writer.buffer(
    #     prefixes: {
    #       nil => "http://example.com/ns#",
    #       foaf: "http://xmlns.com/foaf/0.1/"}
    #   ) do |writer|
    #     graph.each_statement do |statement|
    #       writer << statement
    #     end
    #   end
    #
    # Select the :expand option to output JSON-LD in expanded form
    #
    # @see https://www.w3.org/TR/json-ld11-api/
    # @see https://www.w3.org/TR/json-ld11-api/#the-normalization-algorithm
    # @author [Gregg Kellogg](http://greggkellogg.net/)
    class Writer < RDF::Writer
      include StreamingWriter
      include Utils
      include RDF::Util::Logger
      format Format

      # @!attribute [r] graph
      # @return [RDF::Graph] Graph of statements serialized
      attr_reader :graph

      # @!attribute [r] context
      # @return [Context] context used to load and administer contexts
      attr_reader :context

      ##
      # JSON-LD Writer options
      # @see https://ruby-rdf.github.io/rdf/RDF/Writer#options-class_method
      def self.options
        super + [
          RDF::CLI::Option.new(
            symbol: :compactArrays,
            datatype: TrueClass,
            default: true,
            control: :checkbox,
            on: ["--[no-]compact-arrays"],
            description: "Replaces arrays with just one element with that element during compaction. Default is `true` use --no-compact-arrays to disable."
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :compactToRelative,
            datatype: TrueClass,
            default: true,
            control: :checkbox,
            on: ["--[no-]compact-to-relative"],
            description: "Creates document relative IRIs when compacting, if `true`, otherwise leaves expanded. Default is `true` use --no-compact-to-relative to disable."
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :context,
            datatype: RDF::URI,
            control: :url2,
            on: ["--context CONTEXT"],
            description: "Context to use when compacting."
          ) { |arg| RDF::URI(arg).absolute? ? RDF::URI(arg) : StringIO.new(File.read(arg)) },
          RDF::CLI::Option.new(
            symbol: :embed,
            datatype: %w[@always @once @never],
            default: '@once',
            control: :select,
            on: ["--embed EMBED"],
            description: "How to embed matched objects (@once)."
          ) { |arg| RDF::URI(arg) },
          RDF::CLI::Option.new(
            symbol: :explicit,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]explicit"],
            description: "Only include explicitly declared properties in output (false)"
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :frame,
            datatype: RDF::URI,
            control: :url2,
            use: :required,
            on: ["--frame FRAME"],
            description: "Frame to use when serializing."
          ) { |arg| RDF::URI(arg).absolute? ? RDF::URI(arg) : StringIO.new(File.read(arg)) },
          RDF::CLI::Option.new(
            symbol: :lowercaseLanguage,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]lowercase-language"],
            description: "By default, language tags are left as is. To normalize to lowercase, set this option to `true`."
          ),
          RDF::CLI::Option.new(
            symbol: :omitDefault,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]omitDefault"],
            description: "Omit missing properties from output (false)"
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :ordered,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]ordered"],
            description: "Order object member processing lexographically."
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :processingMode,
            datatype: %w[json-ld-1.0 json-ld-1.1],
            control: :radio,
            on: ["--processingMode MODE", %w[json-ld-1.0 json-ld-1.1]],
            description: "Set Processing Mode (json-ld-1.0 or json-ld-1.1)"
          ),
          RDF::CLI::Option.new(
            symbol: :rdfDirection,
            datatype: %w[i18n-datatype compound-literal],
            default: 'null',
            control: :select,
            on: ["--rdf-direction DIR", %w[i18n-datatype compound-literal]],
            description: "How to serialize literal direction (i18n-datatype compound-literal)"
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :requireAll,
            datatype: TrueClass,
            default: true,
            control: :checkbox,
            on: ["--[no-]require-all"],
            description: "Require all properties to match (true). Default is `true` use --no-require-all to disable."
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :stream,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]stream"],
            description: "Do not attempt to optimize graph presentation, suitable for streaming large graphs."
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :useNativeTypes,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]use-native-types"],
            description: "Use native JSON values in value objects."
          ) { |arg| arg },
          RDF::CLI::Option.new(
            symbol: :useRdfType,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]use-rdf-type"],
            description: "Treat `rdf:type` like a normal property instead of using `@type`."
          ) { |arg| arg }
        ]
      end

      class << self
        attr_reader :white_list, :black_list

        ##
        # Use parameters from accept-params to determine if the parameters are acceptable to invoke this writer. The `accept_params` will subsequently be provided to the writer instance.
        #
        # @param [Hash{Symbol => String}] accept_params
        # @yield [accept_params] if a block is given, returns the result of evaluating that block
        # @yieldparam [Hash{Symbol => String}] accept_params
        # @return [Boolean]
        # @see    http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.1
        def accept?(accept_params)
          if block_given?
            yield(accept_params)
          else
            true
          end
        end

        ##
        # Returns default context used for compacted profile without an explicit context URL
        # @return [String]
        def default_context
          @default_context || JSON::LD::DEFAULT_CONTEXT
        end

        ##
        # Sets default context used for compacted profile without an explicit context URL
        # @param [String] url
        attr_writer :default_context
      end

      ##
      # Initializes the JSON-LD writer instance.
      #
      # @param  [IO, File] output
      #   the output stream
      # @param  [Hash{Symbol => Object}] options
      #   any additional options
      # @option options [Encoding] :encoding     (Encoding::UTF_8)
      #   the encoding to use on the output stream (Ruby 1.9+)
      # @option options [Boolean]  :canonicalize (false)
      #   whether to canonicalize literals when serializing
      # @option options [Hash]     :prefixes     ({})
      #   the prefix mappings to use (not supported by all writers)
      # @option options [Boolean]  :standard_prefixes   (false)
      #   Add standard prefixes to @prefixes, if necessary.
      # @option options [IO, Array, Hash, String, Context]     :context     ({})
      #   context to use when serializing. Constructed context for native serialization.
      # @option options [IO, Array, Hash, String, Context]     :frame     ({})
      #   frame to use when serializing.
      # @option options [Boolean]  :unique_bnodes   (false)
      #   Use unique bnode identifiers, defaults to using the identifier which the node was originall initialized with (if any).
      # @option options [Proc] serializer (JSON::LD::API.serializer)
      #   A Serializer method used for generating the JSON serialization of the result.
      # @option options [Boolean] :stream (false)
      #   Do not attempt to optimize graph presentation, suitable for streaming large graphs.
      # @yield  [writer] `self`
      # @yieldparam  [RDF::Writer] writer
      # @yieldreturn [void]
      # @yield  [writer]
      # @yieldparam [RDF::Writer] writer
      def initialize(output = $stdout, **options, &block)
        options[:base_uri] ||= options[:base] if options.key?(:base)
        options[:base] ||= options[:base_uri] if options.key?(:base_uri)
        @serializer = options.fetch(:serializer, JSON::LD::API.method(:serializer))
        super do
          @repo = RDF::Repository.new

          if block
            case block.arity
            when 0 then instance_eval(&block)
            else yield(self)
            end
          end
        end
      end

      ##
      # Addes a triple to be serialized
      # @param  [RDF::Resource] subject
      # @param  [RDF::URI]      predicate
      # @param  [RDF::Value]    object
      # @return [void]
      # @abstract
      def write_triple(subject, predicate, object)
        write_quad(subject, predicate, object, nil)
      end

      ##
      # Outputs the N-Quads representation of a statement.
      #
      # @param  [RDF::Resource] subject
      # @param  [RDF::URI]      predicate
      # @param  [RDF::Term]     object
      # @return [void]
      def write_quad(subject, predicate, object, graph_name)
        statement = RDF::Statement.new(subject, predicate, object, graph_name: graph_name)
        if @options[:stream]
          stream_statement(statement)
        else
          @repo.insert(statement)
        end
      end

      ##
      # Necessary for streaming
      # @return [void] `self`
      def write_prologue
        stream_prologue if @options[:stream]
        super
      end

      ##
      # Outputs the Serialized JSON-LD representation of all stored statements.
      #
      # If provided a context or prefixes, we'll create a context
      # and use it to compact the output. Otherwise, we return un-compacted JSON-LD
      #
      # @return [void]
      # @see    #write_triple
      def write_epilogue
        if @options[:stream]
          stream_epilogue
        else

          # log_debug("writer") { "serialize #{@repo.count} statements, #{@options.inspect}"}
          result = API.fromRdf(@repo, **@options.merge(serializer: nil))

          # Some options may be indicated from accept parameters
          profile = @options.fetch(:accept_params, {}).fetch(:profile, "").split
          links = LinkHeader.parse(@options[:link])
          @options[:context] ||= begin
            links.find_link(['rel', JSON_LD_NS + "context"]).href
          rescue StandardError
            nil
          end
          @options[:context] ||= Writer.default_context if profile.include?(JSON_LD_NS + "compacted")
          @options[:frame] ||= begin
            links.find_link(['rel', JSON_LD_NS + "frame"]).href
          rescue StandardError
            nil
          end

          # If we were provided a context, or prefixes, use them to compact the output
          context = @options[:context]
          context ||= if @options[:prefixes] || @options[:language] || @options[:standard_prefixes]
            ctx = Context.new(**@options)
            ctx.language = @options[:language] if @options[:language]
            @options[:prefixes]&.each do |prefix, iri|
              ctx.set_mapping(prefix, iri) if prefix && iri
            end
            ctx
          end

          # Rename BNodes to uniquify them, if necessary
          result = API.flatten(result, context, **@options.merge(serializer: nil)) if options[:unique_bnodes]

          if (frame = @options[:frame])
            # Perform framing, if given a frame
            # log_debug("writer") { "frame result"}
            result = API.frame(result, frame, **@options.merge(serializer: nil))
          elsif context
            # Perform compaction, if we have a context
            # log_debug("writer") { "compact result"}
            result = API.compact(result, context, **@options.merge(serializer: nil))
          end

          @output.write(@serializer.call(result, **@options))
        end

        super
      end
    end
  end
end
