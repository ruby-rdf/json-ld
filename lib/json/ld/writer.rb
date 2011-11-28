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
  # @example Creating @base, @vocab and @context prefix definitions in output
  #   JSON::LD::Writer.buffer(
  #     :base_uri => "http://example.com/",
  #     :vocab => "http://example.net/"
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
    # Local implementation of ruby Hash class to allow for ordering in 1.8.x implementations.
    #
    # @return [Hash, InsertOrderPreservingHash]
    def self.new_hash
      if RUBY_VERSION < "1.9"
        InsertOrderPreservingHash.new
      else
        Hash.new
      end
    end
    def new_hash; self.class.new_hash; end

    ##
    # Return the pre-serialized Hash before turning into JSON
    #
    # @return [Hash]
    def self.hash(*args, &block)
      hash = new_hash
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
    # @option options [#to_s]    :base_uri     (nil)
    #   Base IRI used for relativizing IRIs
    # @option options [#to_s]    :vocab     (nil)
    #   Vocabulary prefix used for relativizing IRIs
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

      @context = EvaluationContext.new(@options).parse(@options[:context] || {})
      @context.language = @options[:language].to_sym if @options[:language]
      @context.base = RDF::URI(@options[:base_uri]) if @options[:base_uri] && !(@options[:expand] || @options[:normalize])
      @context.vocab = @options[:vocab] if @options[:vocab] && !(@options[:expand] || @options[:normalize])
      @context.list.each {|p| @list_range[p] = true}

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
      json_hash = (@options[:expand] || @options[:normalize]) ? new_hash : start_document

      elements = []
      order_subjects.each do |subject|
        unless is_done?(subject)
          elements << subject(subject, json_hash)
        end
      end
      
      return if elements.empty?
      
      if elements.length == 1 && elements.first.is_a?(Hash)
        json_hash.merge!(elements.first)
      else
        json_hash['@subject'] = elements
      end
      
      if @output.is_a?(Hash)
        @output.merge!(json_hash)
      else
        json_state = if @options[:normalize]
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
        result = {"@iri" => result}
      end
    
      debug {"=> #{result.inspect}"}
      result
    end
    
    ##
    # @param  [RDF::Node] value
    # @param  [Hash{Symbol => Object}] options
    # @return [String]
    # @raise  [NotImplementedError] unless implemented in subclass
    # @abstract
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
      result = depth do
        if options[:expand] || @options[:normalize]
          debug {"=> expand"}
          ret = new_hash
          ret['@literal'] = literal.value
          ret['@datatype'] = format_iri(literal.datatype, :position => :subject) if literal.has_datatype?
          ret['@language'] = literal.language.to_s if literal.has_language?
          ret.delete_if {|k,v| v.nil?}
        elsif literal.is_a?(RDF::Literal::Integer) || literal.is_a?(RDF::Literal::Boolean)
          debug {"=> object"}
          literal.object
        elsif datatype_range?(options[:property]) || (!literal.has_datatype? && literal.language == context.language)
          # Datatype coercion where literal has the same datatype
          debug {"=> value"}
          literal.value
        elsif literal.plain? && context.language
          debug {"=> language = null"}
          ret = new_hash
          ret['@literal'] = literal.value
          ret
        else
          debug {"=> @literal"}
          ret = new_hash
          ret['@literal'] = literal.value
          ret['@datatype'] = format_iri(literal.datatype, :position => :subject) if literal.has_datatype?
          ret['@language'] = literal.language.to_s if literal.has_language?
          ret
        end
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
    ##
    # Generate @context
    # @return [Hash]
    def start_document
      use_context = case @options[:context]
      when Hash, String
        debug "start:doc: reuse context"
        @options[:context]
      else
        debug("start_doc: create context")
        debug {"=> context: #{context.inspect}"}
        ctx = new_hash
        ctx['@base'] = context.base.to_s if context.base
        ctx['@vocab'] = context.vocab.to_s if context.vocab
        ctx['@language'] = context.language.to_s if context.language

        # Prefixes
        context.mappings.keys.sort {|a,b| a.to_s <=> b.to_s}.each do |k|
          next unless context.term_valid?(k.to_s)
          debug {"=> context.mappings[#{k}] => #{context.mappings[k]}"}
          ctx[k.to_s] = context.mappings[k].to_s
        end

        unless context.coerce.empty? && @list_range.empty?
          ctx2 = new_hash

          # Coerce
          (context.coerce.keys + @list_range.keys).uniq.sort.each do |k|
            next if ['@type', RDF.type.to_s].include?(k.to_s)

            k_iri = context.compact_iri(k, :position => :predicate, :depth => @depth)
            k_prefix = k_iri.to_s.split(':').first

            if context.coerce[k] && ![false, RDF::XSD.integer.to_s, RDF::XSD.boolean.to_s].include?(context.coerce[k])
              # If coercion doesn't depend on any prefix definitions, it can be folded into the first context block
              dt = context.compact_iri(context.coerce[k], :position => :datatype, :depth => @depth)
              dt_prefix = dt.split(':').first
              if ctx[dt_prefix] || (ctx[k_prefix] && k_prefix != k_iri.to_s)
                # It uses a prefix defined above, place in new context block
                ctx2[k_iri.to_s] = new_hash
                ctx2[k_iri.to_s]['@coerce'] = dt
                debug {"=> new coerce[#{k_iri}] => #{dt}"}
              else
                # It is not dependent on previously defined terms, fold into existing definition
                ctx[k_iri] ||= new_hash
                if ctx[k_iri].is_a?(String)
                  defn = new_hash
                  defn["@iri"] = ctx[k_iri]
                  ctx[k_iri] = defn
                end
                ctx[k_iri]["@coerce"] = dt
                debug {"=> reuse coerce[#{k_iri}] => #{dt}"}
              end
            end

            if @list_range[k]
              if ctx2[k_iri.to_s] || (ctx[k_prefix] && k_prefix != k_iri.to_s)
                # Place in second context block
                ctx2[k_iri.to_s] ||= new_hash
                ctx2[k_iri.to_s]['@list'] = true
                debug {"=> new list_range[#{k_iri}] => true"}
              else
                # It is not dependent on previously defined terms, fold into existing definition
                ctx[k_iri] ||= new_hash
                if ctx[k_iri].is_a?(String)
                  defn = new_hash
                  defn["@iri"] = ctx[k_iri]
                  ctx[k_iri] = defn
                end
                ctx[k_iri]["@list"] = true
                debug {"=> reuse list_range[#{k_iri}] => true"}
              end
            end
          end

          # Separate contexts, so uses of prefixes are defined after the definitions of prefixes
          ctx = [ctx, ctx2].reject(&:empty?)
          ctx = ctx.first if ctx.length == 1
        end

        debug {"start_doc: context=#{ctx.inspect}"}
        ctx
      end

      # Return hash with @context, or empty
      r = new_hash
      r['@context'] = use_context unless use_context.nil? || use_context.empty?
      r
    end
    
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
      defn = new_hash
      
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
        defn['@subject'] = format_list(subject)
        properties.delete(RDF.first.to_s)
        properties.delete(RDF.rest.to_s)
        
        # Special case, if there are no properties, then we can just serialize the list itself
        return defn if properties.empty?
      elsif subject.uri? || ref_count(subject) > 1
        debug "subject is an iri or it's a node referenced multiple times"
        # Don't need to set subject if it's a Node without references
        defn['@subject'] = format_iri(subject, :position => :subject)
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
    # Uses context.base.
    # @return [Array<Resource>] Ordered list of subjects
    def order_subjects
      seen = {}
      subjects = []
      
      return @subjects.keys.sort do |a,b|
        format_iri(a, :position => :subject) <=> format_iri(b, :position => :subject)
      end unless @options[:automatic]

      # Start with 
      if context.base && @subjects.keys.include?(context.base)
        subjects << context.base
        seen[context.base] = true
      end
      
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

      unless context.coerce.has_key?(predicate.to_s)
        # objects of all statements with the predicate may not be literal
        context.coerce[predicate.to_s] = !@options[:automatic] ||
          @graph.query(:predicate => predicate).to_a.any? {|st| st.object.literal?} ?
            false :
            '@iri'
      end
      
      debug {"iri_range(#{predicate}) = #{context.coerce[predicate.to_s].inspect}"}
      context.coerce[predicate.to_s] == '@iri'
    end
    
    ##
    # Does predicate have a range of specific typed literal?
    # @param [RDF::URI] predicate
    # @return [Boolean]
    def datatype_range?(predicate)
      unless context.coerce.has_key?(predicate.to_s)
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
          format_iri(dt, :position => :datatype) if dt && ![RDF::XSD.boolean, RDF::XSD.integer].include?(dt)
          debug {"range(#{predicate}) = #{dt.inspect}"}
        else
          dt = false
        end
        context.coerce[predicate.to_s] = dt
      end

      context.coerce[predicate.to_s]
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
        context.list << predicate.to_s if @list_range[predicate.to_s]

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

