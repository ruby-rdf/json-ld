# frozen_string_literal: true

module JSON
  module LD
    ##
    # A JSON-LD parser in Ruby.
    #
    # @see https://www.w3.org/TR/json-ld11-api
    # @author [Gregg Kellogg](http://greggkellogg.net/)
    class Reader < RDF::Reader
      include StreamingReader
      format Format

      ##
      # JSON-LD Reader options
      # @see https://ruby-rdf.github.io/rdf/RDF/Reader#options-class_method
      def self.options
        super + [
          RDF::CLI::Option.new(
            symbol: :expandContext,
            control: :url2,
            datatype: RDF::URI,
            on: ["--expand-context CONTEXT"],
            description: "Context to use when expanding."
          ) { |arg| RDF::URI(arg).absolute? ? RDF::URI(arg) : StringIO.new(File.read(arg)) },
          RDF::CLI::Option.new(
            symbol: :extractAllScripts,
            datatype: TrueClass,
            default: false,
            control: :checkbox,
            on: ["--[no-]extract-all-scripts"],
            description: "If set to true, when extracting JSON-LD script elements from HTML, unless a specific fragment identifier is targeted, extracts all encountered JSON-LD script elements using an array form, if necessary."
          ) { |arg| RDF::URI(arg) },
          RDF::CLI::Option.new(
            symbol: :lowercaseLanguage,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]lowercase-language"],
            description: "By default, language tags are left as is. To normalize to lowercase, set this option to `true`."
          ),
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
          ) { |arg| RDF::URI(arg) },
          RDF::CLI::Option.new(
            symbol: :stream,
            datatype: TrueClass,
            control: :checkbox,
            on: ["--[no-]stream"],
            description: "Optimize for streaming JSON-LD to RDF."
          ) { |arg| arg }
        ]
      end

      ##
      # Initializes the JSON-LD reader instance.
      #
      # @param  [IO, File, String]       input
      # @param  [Hash{Symbol => Object}] options
      #   any additional options (see `RDF::Reader#initialize` and {JSON::LD::API.initialize})
      # @yield  [reader] `self`
      # @yieldparam  [RDF::Reader] reader
      # @yieldreturn [void] ignored
      # @raise [RDF::ReaderError] if the JSON document cannot be loaded
      def initialize(input = $stdin, **options, &block)
        options[:base_uri] ||= options[:base]
        options[:rename_bnodes] = false unless options.key?(:rename_bnodes)
        super do
          @options[:base] ||= base_uri.to_s if base_uri
          # Trim non-JSON stuff in script.
          @doc = if input.respond_to?(:read)
            input
          else
            StringIO.new(input.to_s.sub(/\A[^{\[]*/m, '').sub(/[^}\]]*\Z/m, ''))
          end

          if block
            case block.arity
            when 0 then instance_eval(&block)
            else yield(self)
            end
          end
        end
      end

      ##
      # @private
      # @see   RDF::Reader#each_statement
      def each_statement(&block)
        if @options[:stream]
          stream_statement(&block)
        else
          API.toRdf(@doc, **@options, &block)
        end
      rescue ::JSON::ParserError, ::JSON::LD::JsonLdError => e
        log_fatal("Failed to parse input document: #{e.message}", exception: RDF::ReaderError)
      end

      ##
      # @private
      # @see   RDF::Reader#each_triple
      def each_triple
        if block_given?
          each_statement do |statement|
            yield(*statement.to_triple)
          end
        end
        enum_for(:each_triple)
      end
    end
  end
end
