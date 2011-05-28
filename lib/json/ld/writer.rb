module JSON::LD
  ##
  # A JSON-LD parser in Ruby.
  #
  # Note that the natural interface is to write a whole graph at a time.
  # Writing statements or Triples will create a graph to add them to
  # and then serialize the graph.
  #
  # @example Obtaining a JSON-LD writer class
  #   RDF::Writer.for(:jsonld)         #=> RDF::N3::Writer
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
  # Select the :canonicalize option to output JSON-LD in canonical form
  #
  # @see http://json-ld.org/spec/ED/20110507/
  # @see http://json-ld.org/spec/ED/20110507/#the-normalization-algorithm
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class Writer < RDF::Writer
    format Format

    # @attr [Graph] Graph of statements serialized
    attr :graph
    # @attr [URI] Base IRI used for relativizing IRIs
    attr :base_uri
    # @attr [String] Vocabulary prefix used for relativizing IRIs
    attr :vocab

    # Type coersion to use for serialization. Defaults to DEFAULT_COERCION
    #
    # Maintained as a reverse mapping of `property` => `type`.
    #
    # @attr [Hash{RDF::URI => RDF::URI}]
    attr :coerce, true

    ##
    # Return the pre-serialized Hash before turning into JSON
    #
    # @return [Hash]
    def self.hash(*args, &block)
      hash = {}
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
    # @yield  [writer] `self`
    # @yieldparam  [RDF::Writer] writer
    # @yieldreturn [void]
    # @yield  [writer]
    # @yieldparam [RDF::Writer] writer
    def initialize(output = $stdout, options = {}, &block)
      super do
        @graph = RDF::Graph.new
        @iri_to_prefix = DEFAULT_CONTEXT.dup.delete_if {|k,v| k == "@coerce"}.invert
        @coerce = DEFAULT_COERCE.merge(options[:coerce] || {})
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
      add_debug "Add graph #{graph.inspect}"
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
      @base_uri = RDF::URI(@options[:base_uri]) if @options[:base_uri]
      @vocab = @options[:vocab]
      @debug = @options[:debug]

      reset

      add_debug "\nserialize: graph: #{@graph.size}"

      preprocess
      
      # Don't generate context for canonical output
      json_hash = @options[:canonical] ? {} : start_document

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
        json_hash["@"] = elements
      end
      
      if @output.is_a?(Hash)
        @output.merge!(json_hash)
      else
        json_state = if @options[:canonicalize]
          JSON::State.new(
            :indent       => "",
            :space        => "",
            :space_before => "",
            :object_nl    => "",
            :array_nl     => "",
          )
        else
          JSON::State.new(
            :indent       => "  ",
            :space        => " ",
            :space_before => "",
            :object_nl    => "\n",
            :array_nl     => "\n",
          )
        end
        @output.write(json_hash.to_json(json_state))
      end
    end
    
    ##
    # Returns the representation of a IRI reference.
    #
    # FIXME: IRIs that can't be turned into CURIEs could be returned bare
    # if we knew the range of the property
    #
    # @param  [RDF::URI] value
    # @param  [Hash{Symbol => Object}] options
    # @option options [:subject, :predicate, :object] position
    #   Useful when determining how to serialize.
    # @option options [RDF::URI] property
    #   Property for object reference, which can be used to return
    #   bare strings, rather than {"iri":}
    # @return [Object]
    def format_uri(value, options = {})
      return {:iri => value.to_s} if @options[:canonical]

      result = case options[:position]
      when :subject
        # attempt base_uri replacement
        short = value.to_s.sub(base_uri.to_s, "")
        short == value.to_s ? (get_curie(value) || value.to_s) : short
      when :predicate
        # attempt vocab replacement
        short = "a" if value == RDF.type
        short ||= value.to_s.sub(@vocab.to_s, "")
        short == value.to_s ? (get_curie(value) || value.to_s) : short
      else
        # Encode like a subject
        iri_range?(options[:property]) ?
          format_uri(value, :position => :subject) :
          {:iri => format_uri(value, :position => :subject)}
      end
    
      add_debug("format_uri(#{options.inspect}, #{value.inspect}) => #{result.inspect}")
      result
    end
    
    ##
    # @param  [RDF::Node] value
    # @param  [Hash{Symbol => Object}] options
    # @return [String]
    # @raise  [NotImplementedError] unless implemented in subclass
    # @abstract
    def format_node(value, options = {})
      format_uri(value, options)
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
      if options[:canonical] || @options[:canonicalize]
        return {
          :literal => literal.value,
          :datatype => (format_uri(literal.datatype, :position => :subject) if literal.has_datatype?),
          :language => (literal.language.to_s if literal.has_language?)
        }.delete_if {|k,v| v.nil?}
      end

      case literal
      when RDF::Literal::Integer, RDF::Literal::Boolean
        literal.object
      when RDF::Literal
        if datatype_range?(options[:property]) || !(literal.has_datatype? || literal.has_language?)
          # Datatype coercion where literal has the same datatype
          literal.value
        else
          format_literal(literal, :canonical => true)
        end
      end
    end
    
    ##
    # Serialize an RDF list
    # @param [RDF::URI] object
    # @param  [Hash{Symbol => Object}] options
    # @option options [RDF::URI] property
    #   Property referencing literal for type coercion
    # @return [Array<Array<Object>>]
    def format_list(object, options = {})
      predicate = options[:property]
      list = []

      add_debug "format_list(#{object}, #{predicate})"

      @depth += 1
      while object do
        subject_done(object)
        p = @graph.properties(object)
        item = p.fetch(RDF.first.to_s, []).first
        if item
          add_debug "format_list serialize #{item.inspect}"
          list << if predicate || item.literal?
            property(predicate, item)
          else
            subject(item)
          end
        end
        object = p.fetch(RDF.rest.to_s, []).first
      end
      @depth -= 1
    
      # Returns 
      add_debug "format_list => #{[list].inspect}"
      [list]
    end

    private
    ##
    # Generate @context
    # @return [Hash]
    def start_document
      ctx = {}
      ctx["@base"] = base_uri.to_s if base_uri
      ctx["@vocab"] = vocab.to_s if vocab
      
      # Prefixes
      prefixes.keys.sort {|a,b| a.to_s <=> b.to_s}.each do |k|
        next if DEFAULT_CONTEXT.has_key?(k.to_s)
        add_debug "prefix[#{k}] => #{prefixes[k]}"
        ctx[k.to_s] = prefixes[k].to_s
      end
      
      # Coerce
      add_debug "start_doc: coerce= #{coerce.inspect}"
      unless coerce == DEFAULT_COERCE
        c_h = {}
        coerce.keys.sort.each do |k|
          next if coerce[k] == DEFAULT_COERCE[k]  ||
                  coerce[k] == false ||
                  coerce[k] == RDF::XSD.integer ||
                  coerce[k] == RDF::XSD.boolean
          k_iri = format_uri(k, :position => :predicate)
          d_iri = format_uri(coerce[k], :position => :subject)
          add_debug "coerce[#{k_iri}] => #{d_iri}"
          case c_h[d_iri]
          when nil
            c_h[d_iri] = k_iri
          when Array
            c_h[d_iri] << k_iri
          else
            c_h[d_iri] = [c_h[d_iri], k_iri]
          end
        end
        
        ctx["@coerce"] = c_h unless c_h.empty?
      end

      add_debug "start_doc: context=#{ctx.inspect}"
      # Return hash with @context, or empty
      ctx.empty? ? {} : {"@context" => ctx}
    end
    
    # Perform any preprocessing of statements required
    def preprocess
      # Load defined prefixes
      (@options[:prefixes] || {}).each_pair do |k, v|
        @iri_to_prefix[v.to_s] = k
      end
      @options[:prefixes] = {}  # Will define actual used when matched

      @graph.each {|statement| preprocess_statement(statement)}
    end
    
    # Perform any statement preprocessing required. This is used to perform reference counts and determine required
    # prefixes.
    # @param [Statement] statement
    def preprocess_statement(statement)
      add_debug "preprocess: #{statement.inspect}"
      references = ref_count(statement.object) + 1
      @references[statement.object] = references
      @subjects[statement.subject] = true
      
      # Pre-fetch qnames, to fill prefixes
      get_curie(statement.subject)
      get_curie(statement.predicate)
      if statement.object.literal?
        datatype_range?(statement.predicate)  # To figure out coercion requirements
      else
        iri_range?(statement.predicate)
        get_curie(statement.object)
      end

      @references[statement.predicate] = ref_count(statement.predicate) + 1
    end
    
    # Serialize a subject
    # Option contains referencing property, if this is recursive
    # @return [Hash]
    def subject(subject, options = {})
      defn = {}
      
      raise RDF::WriterError, "Illegal use of subject #{subject.inspect}, not supported" unless subject.resource?

      subject_done(subject)
      properties = @graph.properties(subject)
      add_debug "subject: #{subject.inspect}, props: #{properties.inspect}"

      @graph.query(:subject => subject).each do |st|
        raise RDF::WriterError, "Illegal use of predicate #{st.predicate.inspect}, not supported in RDF/XML" unless st.predicate.uri?
      end

      if subject.node? && ref_count(subject) > (options[:property] ? 1 : 0) && options[:canonicalize]
        raise RDF::WriterError, "Can't serialize named node when normalizing"
      end

      # Subject may be a list
      if is_valid_list?(subject)
        add_debug "subject is a list"
        defn["@"] = format_list(subject)
        properties.delete(RDF.first.to_s)
        properties.delete(RDF.rest.to_s)
        
        # Special case, if there are no properties, then we can just serialize the list itself
        return defn["@"].first if properties.empty?
      elsif subject.uri? || ref_count(subject) > 1
        add_debug "subject is a uri"
        # Don't need to set subject if it's a Node without references
        defn["@"] = format_uri(subject, :position => :subject)
      else
        add_debug "subject is an unreferenced BNode"
      end

      prop_list = order_properties(properties)
      #add_debug "=> property order: #{prop_list.to_sentence}"

      prop_list.each do |prop|
        predicate = RDF::URI.intern(prop)

        p_iri = format_uri(predicate, :position => :predicate)
        @depth += 1
        defn[p_iri] = property(predicate, properties[prop])
        @depth -= 1
      end
      
      add_debug "subject: #{subject} has defn: #{defn.inspect}"
      defn
    end
    
    # Serialize objects for a property
    #
    # @param [RDF::URI] predicate
    # @param [Array<RDF::URI>, RDF::URI] objects
    # @param [Hash{Symbol => Object}] options
    # @return [Array, Hash, Object]
    def property(predicate, objects, options = {})
      objects = objects.first if objects.is_a?(Array) && objects.length == 1
      case objects
      when Array
        objects.map {|o| property(predicate, o, options)}
      when RDF::Literal
        format_literal(objects, options.merge(:property => predicate))
      else
        if is_valid_list?(objects)
          format_list(objects, :property => predicate)
        elsif is_done?(objects) || !@subjects.include?(objects)
          format_uri(objects, :position => :object, :property => predicate)
        else
          subject(objects, :property => predicate)
        end
      end
    end

    ##
    # Return a CURIE for the IRI, or nil. Adds namespace of CURIE to defined prefixes
    # @param [RDF::Resource] resource
    # @return [String, nil] value to use to identify IRI
    def get_curie(resource)
      add_debug "get_curie(#{resource.inspect})"
      case resource
      when RDF::Node
        return resource.to_s
      when RDF::URI
        iri = resource.to_s
        return iri if options[:canonicalize]
      else
        return nil
      end

      curie = case
      when @iri_to_curie.has_key?(iri)
        return @iri_to_curie[iri]
      when u = @iri_to_prefix.keys.detect {|u| iri.index(u.to_s) == 0}
        # Use a defined prefix
        prefix = @iri_to_prefix[u]
        prefix(prefix, u)  # Define for output
        iri.sub(u.to_s, "#{prefix}:")
      when @options[:standard_prefixes] && vocab = RDF::Vocabulary.detect {|v| iri.index(v.to_uri.to_s) == 0}
        prefix = vocab.__name__.to_s.split('::').last.downcase
        @iri_to_prefix[vocab.to_uri.to_s] = prefix
        prefix(prefix, vocab.to_uri) # Define for output
        iri.sub(vocab.to_uri.to_s, "#{prefix}:")
      else
        nil
      end
      
      @iri_to_curie[iri] = curie
    rescue Addressable::URI::InvalidURIError => e
      raise RDF::WriterError, "Invalid IRI #{resource.inspect}: #{e.message}"
    end

    ##
    # Take a hash from predicate IRIs to lists of values.
    # Sort the lists of values.  Return a sorted list of properties.
    # @param [Hash{String => Array<Resource>}] properties A hash of Property to Resource mappings
    # @return [Array<String>}] Ordered list of properties.
    def order_properties(properties)
      # Make sorted list of properties
      prop_list = []
      
      properties.keys.sort do |a,b|
        format_uri(a, :position => :predicate) <=> format_uri(b, :position => :predicate)
      end.each do |prop|
        prop_list << prop.to_s
      end
      
      prop_list
    end

    # Order subjects for output. Override this to output subjects in another order.
    #
    # Uses #base_uri.
    # @return [Array<Resource>] Ordered list of subjects
    def order_subjects
      seen = {}
      subjects = []
      
      # Start with base_uri
      if base_uri && @subjects.keys.include?(base_uri)
        subjects << base_uri
        seen[base_uri] = true
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
      return false if predicate.nil?

      unless coerce.has_key?(predicate)
        # objects of all statements with the predicate may not be literal
       coerce[predicate] = @graph.query(:predicate => predicate).to_a.any? {|st| st.object.literal?} ?
          false : RDF::XSD.anyURI
      end
      
      add_debug "iri_range(#{predicate}) = #{coerce[predicate].inspect}"
      coerce[predicate] == RDF::XSD.anyURI
    end
    
    ##
    # Does predicate have a range of specific typed literal?
    # @param [RDF::URI] predicate
    # @return [Boolean]
    def datatype_range?(predicate)
      unless coerce.has_key?(predicate)
        # objects of all statements with the predicate must be literal
        # and have the same non-nil datatype
        dt = nil
        @graph.query(:predicate => predicate) do |st|
          if st.object.literal? && st.object.has_datatype?
            dt = st.object.datatype if dt.nil?
            dt = false unless dt == st.object.datatype
          else
            dt = false
          end
        end
        add_debug "range(#{predicate}) = #{dt.inspect}"
        coerce[predicate] = dt
      end

      coerce[predicate]
    end
    
    # Reset internal helper instance variables
    def reset
      @depth = 0
      @references = {}
      @serialized = {}
      @subjects = {}
      @iri_to_curie = {}
    end

    # Add debug event to debug array, if specified
    #
    # @param [String] message::
    def add_debug(message)
      msg = "#{" " * @depth * 2}#{message}"
      STDERR.puts msg if ::JSON::LD::debug?
      @debug << msg if @debug.is_a?(Array)
    end
    
    # Checks if l is a valid RDF list, i.e. no nodes have other properties.
    def is_valid_list?(l)
      props = @graph.properties(l)
      unless l.node? && props.has_key?(RDF.first.to_s) || l == RDF.nil
        add_debug "is_valid_list: false, #{l.inspect}: #{props.inspect}"
        return false
      end

      while l && l != RDF.nil do
        #add_debug "is_valid_list(length): #{props.length}"
        return false unless props.has_key?(RDF.first.to_s) && props.has_key?(RDF.rest.to_s)
        n = props[RDF.rest.to_s]
        unless n.is_a?(Array) && n.length == 1
          add_debug "is_valid_list: false, #{n.inspect}"
          return false
        end
        l = n.first
        unless l.node? || l == RDF.nil
          add_debug "is_valid_list: false, #{l.inspect}"
          return false
        end
        props = @graph.properties(l)
      end
      add_debug "is_valid_list: valid"
      true
    end

    def is_done?(subject)
      @serialized.include?(subject)
    end
    
    # Mark a subject as done.
    def subject_done(subject)
      @serialized[subject] = true
    end
  end
end

