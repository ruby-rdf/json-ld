require 'json/ld/utils'

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
  #   RDF::Writer.for(:file_extension => "json")
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
  #     :prefixes => {
  #       nil => "http://example.com/ns#",
  #       :foaf => "http://xmlns.com/foaf/0.1/"}
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
    include Utils
    format Format

    # @attr [RDF::Graph] Graph of statements serialized
    attr :graph
    
    # @attr [EvaluationContext] context used to load and administer contexts
    attr :context

    ##
    # Override normal symbol generation
    def self.to_sym
      :jsonld
    end

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
    # @option options [Hash]     :prefixes     (Hash.ordered)
    #   the prefix mappings to use (not supported by all writers)
    # @option options [Boolean]  :standard_prefixes   (false)
    #   Add standard prefixes to @prefixes, if necessary.
    # @option options [IO, Array, Hash, String, EvaluationContext]     :context     (Hash.ordered)
    #   context to use when serializing. Constructed context for native serialization.
    # @yield  [writer] `self`
    # @yieldparam  [RDF::Writer] writer
    # @yieldreturn [void]
    # @yield  [writer]
    # @yieldparam [RDF::Writer] writer
    def initialize(output = $stdout, options = {}, &block)
      super do
        @graph = RDF::Graph.new

        if block_given?
          case block.arity
            when 0 then instance_eval(&block)
            else block.call(self)
          end
        end
      end
    end

    ##
    # Write whole graph
    #
    # @param  [Graph] graph
    # @return [void]
    def write_graph(graph)
      debug {"Add graph #{graph.inspect}"}
      @graph = graph
    end

    ##
    # Adds a statement to be serialized
    # @param  [RDF::Statement] statement
    # @return [void]
    def write_statement(statement)
      @graph.insert(statement)
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
      @graph.insert(Statement.new(subject, predicate, object))
    end

    ##
    # Outputs the Serialized JSON-LD representation of all stored triples.
    #
    # If provided a context or prefixes, we'll create a context
    # and use it to compact the output. Otherwise, we return un-compacted JSON-LD
    #
    # @return [void]
    # @see    #write_triple
    def write_epilogue
      @debug = @options[:debug]

      # Turn graph into a triple array, ordered by subject
      triples = @graph.each_statement.to_a.sort_by {|s| s.to_ntriples }
      debug("writer") { "serialize #{triples.length} triples, #{@options.inspect}"}
      result = API.fromTriples(triples, @options)

      # If we were provided a context, or prefixes, use them to compact the output
      context = RDF::Util::File.open_file(@options[:context]) if @options[:context].is_a?(String)
      context ||= @options[:context]
      context ||= if @options[:prefixes] || @options[:language] || @options[:standard_prefixes]
        ctx = EvaluationContext.new(@options)
        ctx.language = @options[:language] if @options[:language]
        @options[:prefixes].each do |prefix, iri|
          ctx.set_mapping(prefix, iri)
        end if @options[:prefixes]
        ctx
      end
      
      # Perform compaction, if we have a context
      if context
        debug("writer") { "compact result"}
        result = API.compact(result, context, nil, @options)
      end

      json_state = JSON::State.new(
        :indent       => "  ",
        :space        => " ",
        :space_before => "",
        :object_nl    => "\n",
        :array_nl     => "\n"
      )
      @output.write(result.to_json(json_state))
    end
  end
end

