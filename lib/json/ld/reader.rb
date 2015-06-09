module JSON::LD
  ##
  # A JSON-LD parser in Ruby.
  #
  # @see http://json-ld.org/spec/ED/20110507/
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class Reader < RDF::Reader
    format Format

    ##
    # Initializes the RDF/JSON reader instance.
    #
    # @param  [IO, File, String]       input
    # @param  [Hash{Symbol => Object}] options
    #   any additional options (see `RDF::Reader#initialize` and {JSON::LD::API.initialize})
    # @yield  [reader] `self`
    # @yieldparam  [RDF::Reader] reader
    # @yieldreturn [void] ignored
    # @raise [RDF::ReaderError] if the JSON document cannot be loaded
    def initialize(input = $stdin, options = {}, &block)
      options[:base_uri] ||= options[:base]
      super do
        @options[:base] ||= base_uri.to_s if base_uri
        begin
          # Trim non-JSON stuff in script.
          @doc = if input.respond_to?(:read)
            input
          else
            StringIO.new(input.to_s.sub(%r(\A[^{\[]*)m, '').sub(%r([^}\]]*\Z)m, ''))
          end
        rescue JSON::ParserError => e
          raise RDF::ReaderError, "Failed to parse input document: #{e.message}" if validate?
          @doc = StringIO.new("{}")
        end

        if block_given?
          case block.arity
            when 0 then instance_eval(&block)
            else block.call(self)
          end
        end
      end
    end

    ##
    # @private
    # @see   RDF::Reader#each_statement
    def each_statement(&block)
      JSON::LD::API.toRdf(@doc, @options, &block)
    rescue ::JSON::LD::JsonLdError => e
      raise RDF::ReaderError, e.message
    end

    ##
    # @private
    # @see   RDF::Reader#each_triple
    def each_triple(&block)
      if block_given?
        JSON::LD::API.toRdf(@doc, @options) do |statement|
          yield *statement.to_triple
        end
      end
      enum_for(:each_triple)
    end
  end
end

