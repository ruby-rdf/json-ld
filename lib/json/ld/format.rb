# frozen_string_literal: true

module JSON
  module LD
    ##
    # JSON-LD format specification.
    #
    # @example Obtaining an JSON-LD format class
    #     RDF::Format.for(:jsonld)           #=> JSON::LD::Format
    #     RDF::Format.for("etc/foaf.jsonld")
    #     RDF::Format.for(:file_name         => "etc/foaf.jsonld")
    #     RDF::Format.for(file_extension: "jsonld")
    #     RDF::Format.for(:content_type   => "application/ld+json")
    #
    # @example Obtaining serialization format MIME types
    #     RDF::Format.content_types      #=> {"application/ld+json" => [JSON::LD::Format],
    #                                         "application/x-ld+json" => [JSON::LD::Format]}
    #
    # @example Obtaining serialization format file extension mappings
    #     RDF::Format.file_extensions    #=> {:jsonld => [JSON::LD::Format] }
    #
    # @see https://www.w3.org/TR/json-ld11/
    # @see https://w3c.github.io/json-ld-api/tests/
    class Format < RDF::Format
      content_type     'application/ld+json',
        extension: :jsonld,
        alias: 'application/x-ld+json',
        uri: 'http://www.w3.org/ns/formats/JSON-LD'
      content_encoding 'utf-8'

      reader { JSON::LD::Reader }
      writer { JSON::LD::Writer }

      ##
      # Sample detection to see if it matches JSON-LD
      #
      # Use a text sample to detect the format of an input file. Sub-classes implement
      # a matcher sufficient to detect probably format matches, including disambiguating
      # between other similar formats.
      #
      # @param [String] sample Beginning several bytes (~ 1K) of input.
      # @return [Boolean]
      def self.detect(sample)
        !!sample.match(/\{\s*"@(id|context|type)"/m) &&
          # Exclude CSVW metadata
          !sample.include?("http://www.w3.org/ns/csvw")
      end

      # Specify how to execute CLI commands for each supported format.
      # Derived formats (e.g., YAML-LD) define their own entrypoints.
      LD_FORMATS = {
        jsonld: {
          expand: lambda { |input, **options|
            JSON::LD::API.expand(input,
              serializer: JSON::LD::API.method(:serializer),
                                 **options)
          },
          compact: lambda { |input, **options|
            JSON::LD::API.compact(input,
              options[:context],
              serializer: JSON::LD::API.method(:serializer),
                                  **options)
          },
          flatten: lambda { |input, **options|
            JSON::LD::API.flatten(input,
              options[:context],
              serializer: JSON::LD::API.method(:serializer),
                                  **options)
          },
          frame: lambda { |input, **options|
            JSON::LD::API.frame(input,
              options[:frame],
              serializer: JSON::LD::API.method(:serializer),
                                  **options)
          }
        }
      }

      # Execute the body of a CLI command, generic for each different API method based on definitions on {LD_FORMATS}.
      #
      # Expands the input, or transforms from an RDF format based on the `:format` option, and then executes the appropriate command based on `:output_format` and does appropriate output serialization.
      # @private
      def self.cli_exec(command, files, output: $stdin, **options)
        output.set_encoding(Encoding::UTF_8) if output.respond_to?(:set_encoding) && RUBY_PLATFORM == "java"
        options[:base] ||= options[:base_uri]

        # Parse using input format, serialize using output format
        in_fmt = LD_FORMATS[options.fetch(:format, :jsonld)]
        out_fmt = LD_FORMATS[options.fetch(:output_format, :jsonld)]

        if in_fmt
          # Input is a JSON-LD based source (or derived)
          if files.empty?
            # If files are empty, either use options[:evaluate] or STDIN
            input = options[:evaluate] ? StringIO.new(options[:evaluate]) : $stdin
            input.set_encoding(options.fetch(:encoding, Encoding::UTF_8))
            expanded = in_fmt[:expand].call(input, serializer: nil, **options)
            output.puts out_fmt[command].call(expanded, expanded: true, **options)
          else
            files.each do |file|
              expanded = in_fmt[:expand].call(file, serializer: nil, **options)
              output.puts out_fmt[command].call(expanded, expanded: true, **options)
            end
          end
        else
          # Turn RDF into JSON-LD first
          RDF::CLI.parse(files, **options) do |reader|
            JSON::LD::API.fromRdf(reader, serializer: nil, **options) do |expanded|
              output.puts out_fmt[command].call(expanded, expanded: true, **options)
            end
          end
        end
      end

      ##
      # Hash of CLI commands appropriate for this format:
      #
      # * `expand` => {JSON::LD::API.expand}
      # * `compact` => {JSON::LD::API.compact}
      # * `flatten` => {JSON::LD::API.flatten}
      # * `frame` => {JSON::LD::API.frame}
      #
      # @return [Hash{Symbol => Hash}]
      def self.cli_commands
        {
          expand: {
            description: "Expand JSON-LD or parsed RDF",
            parse: false,
            help: "expand [--context <context-file>] files ...",
            filter: { output_format: LD_FORMATS.keys },  # Only shows output format set
            lambda: lambda do |files, **options|
              options = options.merge(expandContext: options.delete(:context)) if options.key?(:context)
              cli_exec(:expand, files, **options)
            end,
            option_use: { context: :removed }
          },
          compact: {
            description: "Compact JSON-LD or parsed RDF",
            parse: false,
            filter: { output_format: LD_FORMATS.keys },  # Only shows output format set
            help: "compact --context <context-file> files ...",
            lambda: lambda do |files, **options|
              raise ArgumentError, "Compacting requires a context" unless options[:context]

              cli_exec(:compact, files, **options)
            end,
            options: [
              RDF::CLI::Option.new(
                symbol: :context,
                datatype: RDF::URI,
                control: :url2,
                use: :required,
                on: ["--context CONTEXT"],
                description: "Context to use when compacting."
              ) { |arg| RDF::URI(arg).absolute? ? RDF::URI(arg) : StringIO.new(File.read(arg)) }
            ]
          },
          flatten: {
            description: "Flatten JSON-LD or parsed RDF",
            parse: false,
            help: "flatten [--context <context-file>] files ...",
            filter: { output_format: LD_FORMATS.keys },  # Only shows output format set
            lambda: lambda do |files, **options|
              cli_exec(:compact, files, **options)
            end,
            options: [
              RDF::CLI::Option.new(
                symbol: :context,
                datatype: RDF::URI,
                control: :url2,
                use: :required,
                on: ["--context CONTEXT"],
                description: "Context to use when compacting."
              ) { |arg| RDF::URI(arg) },
              RDF::CLI::Option.new(
                symbol: :createAnnotations,
                datatype: TrueClass,
                default: false,
                control: :checkbox,
                on: ["--[no-]create-annotations"],
                description: "Unfold embedded nodes which can be represented using `@annotation`."
              )
            ]
          },
          frame: {
            description: "Frame JSON-LD or parsed RDF",
            parse: false,
            help: "frame --frame <frame-file>  files ...",
            filter: { output_format: LD_FORMATS.keys },  # Only shows output format set
            lambda: lambda do |files, **options|
              raise ArgumentError, "Framing requires a frame" unless options[:frame]

              cli_exec(:compact, files, **options)
            end,
            option_use: { context: :removed },
            options: [
              RDF::CLI::Option.new(
                symbol: :frame,
                datatype: RDF::URI,
                control: :url2,
                use: :required,
                on: ["--frame FRAME"],
                description: "Frame to use when serializing."
              ) { |arg| RDF::URI(arg).absolute? ? RDF::URI(arg) : StringIO.new(File.read(arg)) }
            ]
          }
        }
      end

      ##
      # Override normal symbol generation
      def self.to_sym
        :jsonld
      end

      ##
      # Override normal format name
      def self.name
        "JSON-LD"
      end
    end
  end
end
