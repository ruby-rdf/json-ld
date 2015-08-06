require 'json/ld/streaming_writer'
module JSON::LD
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
  # @see http://json-ld.org/spec/ED/20110507/
  # @see http://json-ld.org/spec/ED/20110507/#the-normalization-algorithm
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class Writer < RDF::Writer
    include StreamingWriter
    include Utils
    format Format

    # @!attribute [r] graph
    # @return [RDF::Graph] Graph of statements serialized
    attr_reader :graph
    
    # @!attribute [r] context
    # @return [Context] context used to load and administer contexts
    attr_reader :context

    ##
    # Initializes the RDF-LD writer instance.
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
    # @option options [Boolean] :stream (false)
    #   Do not attempt to optimize graph presentation, suitable for streaming large graphs.
    # @yield  [writer] `self`
    # @yieldparam  [RDF::Writer] writer
    # @yieldreturn [void]
    # @yield  [writer]
    # @yieldparam [RDF::Writer] writer
    def initialize(output = $stdout, options = {}, &block)
      options[:base_uri] ||= options[:base] if options.has_key?(:base)
      options[:base] ||= options[:base_uri] if options.has_key?(:base_uri)
      super do
        @repo = RDF::Repository.new
        @debug = @options[:debug]

        if block_given?
          case block.arity
            when 0 then instance_eval(&block)
            else block.call(self)
          end
        end
      end
    end

    ##
    # Adds a statement to be serialized
    # @param  [RDF::Statement] statement
    # @return [void]
    def write_statement(statement)
      case
      when @options[:stream]
        stream_statement(statement)
      else
        # Add to repo and output in epilogue
        @repo.insert(statement)
      end
    end

    ##
    # Addes a triple to be serialized
    # @param  [RDF::Resource] subject
    # @param  [RDF::URI]      predicate
    # @param  [RDF::Value]    object
    # @return [void]
    # @raise  [NotImplementedError] unless implemented in subclass
    # @abstract
    def write_triple(subject, predicate, object)
      write_statement(Statement.new(subject, predicate, object))
    end

    ##
    # Necessary for streaming
    # @return [void] `self`
    def write_prologue
      case
      when @options[:stream]
        stream_prologue
      else
        super
      end
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
      return stream_epilogue if @options[:stream]

      debug("writer") { "serialize #{@repo.count} statements, #{@options.inspect}"}
      result = API.fromRdf(@repo, @options)

      # If we were provided a context, or prefixes, use them to compact the output
      context = RDF::Util::File.open_file(@options[:context]) if @options[:context].is_a?(String)
      context ||= @options[:context]
      context ||= if @options[:prefixes] || @options[:language] || @options[:standard_prefixes]
        ctx = Context.new(@options)
        ctx.language = @options[:language] if @options[:language]
        @options[:prefixes].each do |prefix, iri|
          ctx.set_mapping(prefix, iri) if prefix && iri
        end if @options[:prefixes]
        ctx
      end

      # Rename BNodes to uniquify them, if necessary
      if options[:unique_bnodes]
        result = API.flatten(result, context, @options)
      end

      frame = RDF::Util::File.open_file(@options[:frame]) if @options[:frame].is_a?(String)
      if frame ||= @options[:frame]
        # Perform framing, if given a frame
        debug("writer") { "frame result"}
        result = API.frame(result, frame, @options)
      elsif context
        # Perform compaction, if we have a context
        debug("writer") { "compact result"}
        result = API.compact(result, context,  @options)
      end

      @output.write(result.to_json(JSON_STATE))
    end
  end
end

