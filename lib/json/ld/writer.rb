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
    format Format

    # @attr [RDF::Graph] Graph of statements serialized
    attr :graph
    
    # @attr [EvaluationContext] context used to load and administer contexts
    attr :context

    ##
    # Return the pre-serialized Hash before turning into JSON
    #
    # @return [Hash]
    def self.hash(*args, &block)
      hash = Hash.new
      self.new(hash, *args, &block)
      hash
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
    # @option options [Hash]     :prefixes     (Hash.new)
    #   the prefix mappings to use (not supported by all writers)
    # @option options [Boolean]  :standard_prefixes   (false)
    #   Add standard prefixes to @prefixes, if necessary.
    # @option options [IO, Array, Hash, String, EvaluationContext]     :context     (Hash.new)
    #   context to use when serializing. Constructed context for native serialization.
    # @option options [Boolean] :automatic (true)
    #   Automatically create context coercions and generate compacted form
    # @option options [Boolean] :expand (false)
    #   Output document in [expanded form](http://json-ld.org/spec/latest/json-ld-api/#expansion)
    # @option options [Boolean] :compact (false)
    #   Output document in [compacted form](http://json-ld.org/spec/latest/json-ld-api/#compaction).
    #   Requires a referenced evaluation context
    # @option options [Boolean] :normalize (false)
    #   Output document in [normalized form](http://json-ld.org/spec/latest/json-ld-api/#normalization)
    # @option options [IO, Array, Hash, String] :frame
    #   Output document in [framed form](http://json-ld.org/spec/latest/json-ld-api/#framing)
    #   using the referenced document as a frame.
    # @yield  [writer] `self`
    # @yieldparam  [RDF::Writer] writer
    # @yieldreturn [void]
    # @yield  [writer]
    # @yieldparam [RDF::Writer] writer
    def initialize(output = $stdout, options = {}, &block)
      super do
        @graph = RDF::Graph.new
        @options[:automatic] = true unless [:automatic, :expand, :compact, :frame, :normalize].any? {|k| options.has_key?(k)}

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
    # Addes a statement to be serialized
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
    # @return [void]
    # @see    #write_triple
    def write_epilogue
      @debug = @options[:debug]

      reset
      
      raise RDF::WriterError, "Compaction requres a context" if @options[:compact] && !@options[:context]

      @context = EvaluationContext.new(@options)
      @context = @context.parse(@options[:context]) if @options[:context]
      @context.language = @options[:language] if @options[:language]
      @context.lists.each {|p| @list_range[p] = true}

      debug {"\nserialize: graph: #{@graph.size}"}
      debug {"=> options: #{@options.reject {|k,v| k == :debug}.inspect}"}
      debug {"=> context: #{@context.inspect}"}

      preprocess

      # Update prefix mappings to those defined in context
      @options[:prefixes] = {}
      @context.iri_to_term.each_pair do |iri, term|
        debug {"add prefix #{term.inspect} for #{iri}"}
        prefix(term, iri)  # Define for output
      end

      # Don't generate context for expanded or normalized output
      json_hash = (@options[:expand] || @options[:normalize]) ? Hash.new : context.serialize(:depth => @depth)

      elements = []
      order_subjects.each do |subject|
        unless is_done?(subject)
          elements << subject(subject, json_hash)
        end
      end
      
      return if elements.empty?
      
      # If there are more than one top-level subjects, place in an array form
      if elements.length == 1 && elements.first.is_a?(Hash)
        json_hash.merge!(elements.first)
      else
        json_hash['@id'] = elements
      end
      
      if @output.is_a?(Hash)
        @output.merge!(json_hash)
      else
        json_state = if @options[:normalize]
          # Normalization uses a compressed form
          JSON::State.new(
            :indent       => "",
            :space        => "",
            :space_before => "",
            :object_nl    => "",
            :array_nl     => ""
          )
        else
          JSON::State.new(
            :indent       => "  ",
            :space        => " ",
            :space_before => "",
            :object_nl    => "\n",
            :array_nl     => "\n"
          )
        end
        @output.write(json_hash.to_json(json_state))
      end
    end
    
    ##
    # Returns the representation of a IRI reference.
    #
    # Spec confusion: should a subject IRI be normalized?
    #
    # @param  [RDF::URI] value
    # @param  [Hash{Symbol => Object}] options
    # @option options [:subject, :predicate, :object] position
    #   Useful when determining how to serialize.
    # @option options [RDF::URI] property
    #   Property for object reference, which can be used to return bare strings
    # @return [Object]
    def format_iri(value, options = {})
      debug {"format_iri(#{options.inspect}, #{value.inspect})"}

      result = context.compact_iri(value, {:depth => @depth}.merge(options))
      unless options[:position] != :object || iri_range?(options[:property])
        result = {"@id" => result}
      end
    
      debug {"=> #{result.inspect}"}
      result
    end
    
    ##
    # @param  [RDF::Node] value
    # @param  [Hash{Symbol => Object}] options
    # @return [String]
    # @raise  [NotImplementedError] unless implemented in subclass
    # @see {#format\_iri}
    def format_node(value, options = {})
      format_iri(value, options)
    end

    ##
    # Returns the representation of a literal.
    #
    # @param  [RDF::Literal, String, #to_s] literal
    # @param  [Hash{Symbol => Object}] options
    # @option options [RDF::URI] property
    #   Property referencing literal for type coercion
    # @return [Object]
    def format_literal(literal, options = {})
      debug {"format_literal(#{options.inspect}, #{literal.inspect})"}

      value = Hash.new
      value['@literal'] = literal.value
      value['@type'] = literal.datatype.to_s if literal.has_datatype?
      value['@language'] = literal.language.to_s if literal.has_language?

      result = case literal
      when RDF::Literal::Boolean, RDF::Literal::Integer, RDF::Literal::Double
        literal.object
      else
        context.compact_value(options[:property], value, {:depth => @depth}.merge(options))
      end

      debug {"=> #{result.inspect}"}
      result
    end
    
    ##
    # Serialize an RDF list
    #
    # @param [RDF::URI] object
    # @param  [Hash{Symbol => Object}] options
    # @option options [RDF::URI] property
    #   Property referencing literal for type and list coercion
    # @return [Hash{"@list" => Array<Object>}]
    def format_list(object, options = {})
      predicate = options[:property]
      list = RDF::List.new(object, @graph)
      ary = []

      debug {"format_list(#{list.inspect}, #{predicate})"}

      depth do
        list.each_statement do |st|
          next unless st.predicate == RDF.first
          debug {" format_list this: #{st.subject} first: #{st.object}"}
          ary << if predicate || st.object.literal?
            property(predicate, st.object)
          else
            subject(st.object)
          end
          subject_done(st.subject)
        end
      end
    
      # Returns
      ary = {'@list' => ary} unless predicate && list_range?(predicate)
      debug {"format_list => #{ary.inspect}"}
      ary
    end

    private
    # Perform any preprocessing of statements required
    def preprocess
      @graph.each {|statement| preprocess_statement(statement)}
    end
    
    # Perform any statement preprocessing required. This is used to perform reference counts and determine required
    # prefixes.
    #
    # @param [Statement] statement
    def preprocess_statement(statement)
      debug {"preprocess: #{statement.inspect}"}
      references = ref_count(statement.object) + 1
      @references[statement.object] = references
      @subjects[statement.subject] = true
      
      depth do
        # Pre-fetch qnames, to fill prefixes
        format_iri(statement.subject, :position => :subject)
        format_iri(statement.predicate, :position => :predicate)
      
        # To figure out coercion requirements
        if statement.object.literal?
          format_literal(statement.object, :property => statement.predicate)
          datatype_range?(statement.predicate)
        else
          format_iri(statement.object, :position => :object)
          iri_range?(statement.predicate)
        end
        list_range?(statement.predicate)
      end

      @references[statement.predicate] = ref_count(statement.predicate) + 1
    end
    
    # Serialize a subject
    # Option contains referencing property, if this is recursive
    # @return [Hash]
    def subject(subject, options = {})
      defn = Hash.new
      
      raise RDF::WriterError, "Illegal use of subject #{subject.inspect}, not supported" unless subject.resource?

      subject_done(subject)
      properties = @graph.properties(subject)
      debug {"subject: #{subject.inspect}, props: #{properties.inspect}"}

      @graph.query(:subject => subject).each do |st|
        raise RDF::WriterError, "Illegal use of predicate #{st.predicate.inspect}, not supported in RDF/XML" unless st.predicate.uri?
      end

      if subject.node? && ref_count(subject) > (options[:property] ? 1 : 0) && options[:expand]
        raise RDF::WriterError, "Can't serialize named node when normalizing"
      end

      # Subject may be a list
      if is_valid_list?(subject)
        debug "subject is a list"
        defn['@id'] = format_list(subject)
        properties.delete(RDF.first.to_s)
        properties.delete(RDF.rest.to_s)
        
        # Special case, if there are no properties, then we can just serialize the list itself
        return defn if properties.empty?
      elsif subject.uri? || ref_count(subject) > 1
        debug "subject is an iri or it's a node referenced multiple times"
        # Don't need to set subject if it's a Node without references
        defn['@id'] = format_iri(subject, :position => :subject)
      else
        debug "subject is an unreferenced BNode"
      end

      prop_list = order_properties(properties)
      debug {"=> property order: #{prop_list.inspect}"}

      prop_list.each do |prop|
        predicate = RDF::URI.intern(prop)

        p_iri = format_iri(predicate, :position => :predicate)
        depth do
          defn[p_iri] = property(predicate, properties[prop])
          debug {"prop(#{p_iri}) => #{properties[prop]} => #{defn[p_iri].inspect}"}
        end
      end
      
      debug {"subject: #{subject} has defn: #{defn.inspect}"}
      defn
    end
    
    ##
    # Serialize objects for a property
    #
    # Spec confusion: sorting of multi-valued properties not adequately specified.
    #
    # @param [RDF::URI] predicate
    # @param [Array<RDF::URI>, RDF::URI] objects
    # @param [Hash{Symbol => Object}] options
    # @return [Array, Hash, Object]
    def property(predicate, objects, options = {})
      objects = objects.first if objects.is_a?(Array) && objects.length == 1
      case objects
      when Array
        objects.sort_by(&:to_s).map {|o| property(predicate, o, options)}
      when RDF::Literal
        format_literal(objects, options.merge(:property => predicate))
      else
        if is_valid_list?(objects)
          format_list(objects, :property => predicate)
        elsif is_done?(objects) || !@subjects.include?(objects)
          format_iri(objects, :position => :object, :property => predicate)
        else
          subject(objects, :property => predicate)
        end
      end
    end

    ##
    # Take a hash from predicate IRIs to lists of values.
    # Sort the lists of values.  Return a sorted list of properties.
    # @param [Hash{String => Array<Resource>}] properties A hash of Property to Resource mappings
    # @return [Array<String>}] Ordered list of properties.
    def order_properties(properties)
      # Make sorted list of properties
      prop_list = []
      
      properties.keys.sort do |a, b|
        format_iri(a, :position => :predicate) <=> format_iri(b, :position => :predicate)
      end.each do |prop|
        prop_list << prop.to_s
      end
      
      prop_list
    end

    # Order subjects for output. Override this to output subjects in another order.
    #
    # @return [Array<Resource>] Ordered list of subjects
    def order_subjects
      seen = {}
      subjects = []
      
      return @subjects.keys.sort do |a,b|
        format_iri(a, :position => :subject) <=> format_iri(b, :position => :subject)
      end unless @options[:automatic]

      # Sort subjects by resources over bnodes, ref_counts and the subject URI itself
      recursable = @subjects.keys.
        select {|s| !seen.include?(s)}.
        map {|r| [r.is_a?(RDF::Node) ? 1 : 0, ref_count(r), r]}.
        sort
      
      subjects += recursable.map{|r| r.last}
    end

    # Return the number of times this node has been referenced in the object position
    # @return [Integer]
    def ref_count(node)
      @references.fetch(node, 0)
    end

    ##
    # Does predicate have a range of IRI?
    # @param [RDF::URI] predicate
    # @return [Boolean]
    def iri_range?(predicate)
      return false if predicate.nil? || [RDF.first, RDF.rest].include?(predicate) || @options[:expand]
      return true if predicate == RDF.type

      unless context.coerce(predicate)
        not_iri = !@options[:automatic]
        #debug {"  (automatic) = #{(!not_iri).inspect}"}
        
        # Any literal object makes it not so
        not_iri ||= @graph.query(:predicate => predicate).to_a.any? do |st|
          l = RDF::List.new(st.object, @graph)
          #debug {"  o.literal? #{st.object.literal?.inspect}"}
          #debug {"  l.valid? #{l.valid?.inspect}"}
          #debug {"  l.any.valid? #{l.to_a.any?(&:literal?).inspect}"}
          st.object.literal? || (l.valid? && l.to_a.any?(&:literal?))
        end
        #debug {"  (literal) = #{(!not_iri).inspect}"}
        
        # FIXME: detect when values are all represented through chaining
        
        context.coerce(predicate, not_iri ? false : '@id')
      end
      
      debug {"iri_range(#{predicate}) = #{context.coerce(predicate).inspect}"}
      context.coerce(predicate) == '@id'
    end
    
    ##
    # Does predicate have a range of specific typed literal?
    # @param [RDF::URI] predicate
    # @return [Boolean]
    def datatype_range?(predicate)
      unless context.coerce(predicate)
        # objects of all statements with the predicate must be literal
        # and have the same non-nil datatype
        dt = nil
        if @options[:automatic]
          @graph.query(:predicate => predicate) do |st|
            debug {"datatype_range? literal? #{st.object.literal?.inspect} dt? #{(st.object.literal? && st.object.has_datatype?).inspect}"}
            if st.object.literal? && st.object.has_datatype?
              dt = st.object.datatype.to_s if dt.nil?
              debug {"=> dt: #{st.object.datatype}"}
              dt = false unless dt == st.object.datatype.to_s
            else
              dt = false
            end
          end
          # Cause necessary prefixes to be output
          format_iri(dt, :position => :datatype) if dt && !NATIVE_DATATYPES.include?(dt.to_s)
          debug {"range(#{predicate}) = #{dt.inspect}"}
        else
          dt = false
        end
        context.coerce(predicate, dt)
      end

      context.coerce(predicate)
    end
    
    ##
    # Is every use of the predicate an RDF Collection?
    #
    # @param [RDF::URI] predicate
    # @return [Boolean]
    def list_range?(predicate)
      return false if [RDF.first, RDF.rest].include?(predicate)

      unless @list_range.include?(predicate.to_s)
        # objects of all statements with the predicate must be a list
        @list_range[predicate.to_s] = if @options[:automatic]
          @graph.query(:predicate => predicate).to_a.all? do |st|
            is_valid_list?(st.object)
          end
        else
          false
        end
        context.list(predicate, true) if @list_range[predicate.to_s]

        debug {"list(#{predicate}) = #{@list_range[predicate.to_s].inspect}"}
      end

      @list_range[predicate.to_s]
    end
    
    # Reset internal helper instance variables
    def reset
      @depth = 0
      @references = {}
      @serialized = {}
      @subjects = {}
      @list_range = {}
    end

    # Checks if l is a valid RDF list, i.e. no nodes have other properties.
    def is_valid_list?(l)
      #debug {"is_valid_list: #{l.inspect}"}
      return RDF::List.new(l, @graph).valid?
    end

    def is_done?(subject)
      @serialized.include?(subject)
    end
    
    # Mark a subject as done.
    def subject_done(subject)
      @serialized[subject] = true
    end

    # Add debug event to debug array, if specified
    #
    # @param [String] message
    # @yieldreturn [String] appended to message, to allow for lazy-evaulation of message
    def debug(*args)
      return unless ::JSON::LD.debug? || @options[:debug]
      message = " " * @depth * 2 + (args.empty? ? "" : args.join(": "))
      message += yield if block_given?
      puts message if JSON::LD::debug?
      @options[:debug] << message if @options[:debug].is_a?(Array)
    end
    
    # Increase depth around a method invocation
    def depth
      @depth += 1
      ret = yield
      @depth -= 1
      ret
    end
  end
end

