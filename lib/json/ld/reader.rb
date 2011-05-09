module JSON::LD
  ##
  # A JSON-LD parser in Ruby.
  #
  # @see http://json-ld.org/spec/ED/20110507/
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class Reader < RDF::Reader
    format Format
    
    # Default context
    # @see http://json-ld.org/spec/ED/20110507/#the-default-context
    DEFAULT_CONTEXT = {
      "rdf"           => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
      "rdfs"          => "http://www.w3.org/2000/01/rdf-schema#",
      "owl"           => "http://www.w3.org/2002/07/owl#",
      "xsd"           => "http://www.w3.org/2001/XMLSchema#",
      "dcterms"       => "http://purl.org/dc/terms/",
      "foaf"          => "http://xmlns.com/foaf/0.1/",
      "cal"           => "http://www.w3.org/2002/12/cal/ical#",
      "vcard"         => "http://www.w3.org/2006/vcard/ns# ",
      "geo"           => "http://www.w3.org/2003/01/geo/wgs84_pos#",
      "cc"            => "http://creativecommons.org/ns#",
      "sioc"          => "http://rdfs.org/sioc/ns#",
      "doap"          => "http://usefulinc.com/ns/doap#",
      "com"           => "http://purl.org/commerce#",
      "ps"            => "http://purl.org/payswarm#",
      "gr"            => "http://purl.org/goodrelations/v1#",
      "sig"           => "http://purl.org/signature#",
      "ccard"         => "http://purl.org/commerce/creditcard#",
      "@coerce"       => {
        # Note: rdf:type is not in the document, but necessary for this implementation
        "xsd:anyURI"  => ["rdf:type", "foaf:homepage", "foaf:member", "rdf:type"],
        "xsd:integer" => "foaf:age",
      }
    }.freeze

    ##
    # The graph constructed when parsing.
    #
    # @return [RDF::Graph]
    attr_reader :graph

    ##
    # Context
    #
    # The `@context` keyword is used to change how the JSON-LD processor evaluates key- value pairs. In this
    # case, it was used to map one string (`'myvocab'`) to another string, which is interpreted as a IRI. In the
    # example above, the `myvocab` string is replaced with "http://example.org/myvocab#" when it is detected. In
    # the example above, `"myvocab:personality"` would expand to "http://example.org/myvocab#personality".
    #
    # This mechanism is a short-hand for RDF, called a `CURIE`, and provides developers an unambiguous way to
    # map any JSON value to RDF.
    #
    # @private
    class EvaluationContext # :nodoc:
      # The base.
      #
      # The `@base` string is a special keyword that states that any relative IRI MUST be appended to the string
      # specified by `@base`.
      #
      # @attr [RDF::URI]
      attr :base, true

      # A list of current, in-scope URI mappings.
      #
      # @attr [Hash{Symbol => String}]
      attr :mappings, true

      # The default vocabulary
      #
      # A value to use as the prefix URI when a term is used.
      # This specification does not define an initial setting for the default vocabulary.
      # Host Languages may define an initial setting.
      #
      # @attr [String]
      attr :vocab, true

      # Type coersion
      #
      # The @coerce keyword is used to specify type coersion rules for the data. For each key in the map, the
      # key is the type to be coerced to and the value is the vocabulary term to be coerced. Type coersion for
      # the key `xsd:anyURI` asserts that all vocabulary terms listed should undergo coercion to an IRI,
      # including `@base` processing for relative IRIs and CURIE processing for compact URI Expressions like
      # `foaf:homepage`.
      #
      # As the value may be an array, this is maintained as a reverse mapping of `property` => `type`.
      #
      # @attr [Hash{RDF::URI => RDF::URI}]
      attr :coerce, true

      ##
      # Create new evaluation context
      # @yield [ec]
      # @yieldparam [EvaluationContext]
      # @return [EvaluationContext]
      def initialize
        @base = nil
        @mappings =  {}
        @vocab = nil
        @coerce = {}
        yield(self) if block_given?
      end

      def inspect
        v = %w([EvaluationContext) + %w(base vocab).map {|a| "#{a}='#{self.send(a).inspect}'"}
        v << "mappings[#{mappings.keys.length}]"
        v << "coerce[#{coerce.keys.length}]"
        v.join(", ") + "]"
      end
    end

    ##
    # Initializes the RDF/JSON reader instance.
    #
    # @param  [IO, File, String]       input
    # @param  [Hash{Symbol => Object}] options
    #   any additional options (see `RDF::Reader#initialize`)
    # @yield  [reader] `self`
    # @yieldparam  [RDF::Reader] reader
    # @yieldreturn [void] ignored
    def initialize(input = $stdin, options = {}, &block)
      super do
        @base_uri = uri(options[:base_uri]) if options[:base_uri]
        @doc = ::JSON.load(input)

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
      @callback = block

      # initialize the evaluation context with the appropriate base
      ec = EvaluationContext.new do |ec|
        ec.base = @base_uri if @base_uri
        parse_context(ec, DEFAULT_CONTEXT)
      end

      traverse("", @doc, nil, nil, ec)
    end

    ##
    # @private
    # @see   RDF::Reader#each_triple
    def each_triple(&block)
      each_statement do |statement|
        block.call(*statement.to_triple)
      end
    end
    
    private
    ##
    #
    # @param [String] path
    #   location within JSON hash
    # @param [Hash, Array, String] element
    #   The current JSON element being processed
    # @param [RDF::URI] subject
    #   Inherited subject
    # @param [RDF::URI] property
    #   Inherited property
    # @param [EvaluationContext] ec
    #   The active context
    def traverse(path, element, subject, property, ec)
      add_debug(path, "traverse: s=#{subject.inspect}, p=#{property.inspect}, e=#{ec.inspect}")
      object = nil

      case element
      when Hash
        # 2) ... For each key-value
        # pair in the associative array, using the newly created processor state do the
        # following:
        
        # 2.1) If a @context keyword is found, the processor merges each key-value pair in
        # the local context into the active context ...
        if element["@context"]
          # Merge context
          ec = parse_context(ec.dup, element["@context"])
          prefixes.merge!(ec.mappings)  # Update parsed prefixes
        end
        
        # Other shortcuts to allow use of this method for terminal associative arrays
        if element["@iri"].is_a?(String)
          # Return the IRI found from the value
          object = expand_term(element["@iri"], ec.base, ec)
          add_triple(path, subject, property, object) if subject && property
        elsif element["@literal"]
          literal_opts = {}
          literal_opts[:datatype] = expand_term(element["@datatype"], ec.vocab.to_s, ec) if element["@datatype"]
          literal_opts[:language] = element["@language"].to_sym if element["@language"]
          object = RDF::Literal.new(element["@literal"], literal_opts)
          add_triple(path, subject, property, object) if subject && property
        end
        
        # 2.2) ... Otherwise, if the local context is known perform the following steps:
        #   2.2.1) If a @ key is found, the processor sets the active subject to the
        #         value after Object Processing has been performed.
        if element["@"].is_a?(String)
          active_subject = expand_term(element["@"], ec.base, ec)
          
          # 2.2.1.1) If the inherited subject and inherited property values are
          # specified, generate a triple using the inherited subject for the
          # subject, the inherited property for the property, and the active
          # subject for the object.
          add_triple(path, subject, property, active_subject) if subject && property
          
          subject = active_subject
        else
          # 2.2.7) If the end of the associative array is detected, and a active subject
          # was not discovered, then:
          #   2.2.7.1) Generate a blank node identifier and set it as the active subject.
          subject = RDF::Node.new
        end
        
        element.each do |key, value|
          # 2.2.3) If a key that is not @context, @, or a, set the active property by
          # performing Property Processing on the key.
          property = case key
          when /^@/
            nil
          when 'a'
            RDF.type
          else
            expand_term(key, ec.vocab, ec)
          end

          traverse("#{path}[#{key}]", value, subject, property, ec) if property
        end
      when Array
        # 3) If a regular array is detected, process each value in the array by doing the following:
        element.each_with_index do |v, i|
          case v
          when Hash, String
            traverse("#{path}[#{i}]", v, subject, property, ec)
          when Array
            # 3.3) If the value is a regular array, should we support RDF List/Sequence Processing?
            last = v.pop
            first_bnode = last ? RDF::Node.new : RDF.nil            
            add_triple("#{path}[#{i}][]", subject, property, first_bnode)

            v.each do |list_item|
              traverse("#{path}[#{i}][]", list_item, first_bnode, RDF.first, ec)
              rest_bnode = RDF::Node.new
              add_triple("#{path}[#{i}][]", first_bnode, RDF.rest, rest_bnode)
              first_bnode = rest_bnode
            end
            if last
              traverse("#{path}[#{i}][]", last, first_bnode, RDF.first, ec)
              add_triple("#{path}[#{i}][]", first_bnode, RDF.rest, RDF.nil)
            end
          end
        end
      when String
        # Perform coersion of the value, or generate a literal
        add_debug(path, "traverse(#{element}): coerce?(#{property.inspect}) == #{ec.coerce[property].inspect}, ec=#{ec.coerce.inspect}")
        object = if ec.coerce[property] == RDF::XSD.anyURI
          expand_term(element, ec.base, ec)
        elsif ec.coerce[property]
          RDF::Literal.new(element, :datatype => ec.coerce[property])
        else
          RDF::Literal.new(element)
        end
        add_triple(path, subject, property, object) if subject && property
      when Float
        object = RDF::Literal::Double.new(element)
        add_debug(path, "traverse(#{element}): native: #{object.inspect}")
        add_triple(path, subject, property, object) if subject && property
      when Fixnum
        object = RDF::Literal.new(element)
        add_debug(path, "traverse(#{element}): native: #{object.inspect}")
        add_triple(path, subject, property, object) if subject && property
      when TrueClass, FalseClass
        object = RDF::Literal::Boolean.new(element)
        add_debug(path, "traverse(#{element}): native: #{object.inspect}")
        add_triple(path, subject, property, object) if subject && property
      else
        raise RDF::ReaderError, "Traverse to unknown element: #{element.inspect} of type #{element.class}"
      end
    end

    ##
    # add a statement, object can be literal or URI or bnode
    #
    # @param [String] path
    # @param [URI, BNode] subject the subject of the statement
    # @param [URI] predicate the predicate of the statement
    # @param [URI, BNode, Literal] object the object of the statement
    # @return [Statement] Added statement
    # @raise [ReaderError] Checks parameter types and raises if they are incorrect if parsing mode is _validate_.
    def add_triple(path, subject, predicate, object)
      statement = RDF::Statement.new(subject, predicate, object)
      add_debug(path, "statement: #{statement.to_ntriples}")
      @callback.call(statement)
    end

    ##
    # Add debug event to debug array, if specified
    #
    # @param [XML Node, any] node:: XML Node or string for showing context
    # @param [String] message::
    def add_debug(node, message)
      puts "#{node}: #{message}" if JSON::LD::debug?
      @options[:debug] << "#{node}: #{message}" if @options[:debug].is_a?(Array)
    end

    ##
    # Parse a JSON context, into a new EvaluationContext
    # @param [Hash{String => String,Hash}] context
    #   JSON representation of @context
    # @return [EvaluationContext]
    # @raise [RDF::ReaderError] on a syntax error, or a reference to a term which is not defined.
    def parse_context(ec, context)
      context.each do |key, value|
        #add_debug("parse_context(#{key})", value.inspect)
        case key
        when '@vocab' then ec.vocab = value
        when '@base'  then ec.base  = uri(value)
        when '@coerce'
          # Spec confusion: doc says to merge each key-value mapping to the local context's @coerce mapping,
          # overwriting duplicate values. In the case where a mapping is indicated to a list of properties
          # (e.g., { "xsd:anyURI": ["foaf:homepage", "foaf:member"] }, does this overwrite a previous mapping
          # of { "xsd:anyURI": "foaf:knows" }, or add to it.
          add_error RDF::ReaderError, "Expected @coerce to reference an associative array" unless value.is_a?(Hash)
          value.each do |type, property|
            type_uri = expand_term(type, ec.vocab, ec)
            [property].flatten.compact.each do |prop|
              p = expand_term(prop, ec.vocab, ec)
              ec.coerce[p] = type_uri
            end
          end
        else
          # Spec confusion: The text indicates to merge each key-value pair into the active context. Is any
          # processing performed on the values. For instance, could a value be a CURIE, or {"@iri": <value>}?
          # Examples indicate that there is no such processing, and each value should be an absolute IRI. The
          # wording makes this unclear.
          ec.mappings[key.to_sym] = value
        end
      end
      
      ec
    end
    
    ##
    # Expand a term using the specified context
    #
    # @param [String] term
    # @param [String] base Base to apply to URIs
    # @param [EvaluationContext] ec
    #
    # @return [RDF::URI]
    # @raise [RDF::ReaderError] if the term cannot be expanded
    # @see http://json-ld.org/spec/ED/20110507/#markup-of-rdf-concepts
    def expand_term(term, base, ec)
      #add_debug("expand_term", "term=#{term.inspect}, base=#{base.inspect}, ec=#{ec.inspect}")
      prefix, suffix = term.split(":", 2)
      prefix = prefix.to_sym if prefix
      return  if prefix == '_'
      if prefix == :_
        bnode(suffix)
      elsif ec.mappings.has_key?(prefix)
        uri(ec.mappings[prefix] + suffix.to_s)
      elsif base
        base.respond_to?(:join) ? base.join(term) : uri(base + term)
      else
        uri(term)
      end
    end

    def uri(value, append = nil)
      value = RDF::URI.new(value)
      value = value.join(append) if append
      value.validate! if validate?
      value.canonicalize! if canonicalize?
      value = RDF::URI.intern(value) if intern?
      value
    end

    # Keep track of allocated BNodes
    def bnode(value = nil)
      @bnode_cache ||= {}
      @bnode_cache[value.to_s] ||= RDF::Node.new(value)
    end
  end
end

