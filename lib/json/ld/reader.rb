require 'open-uri'

module JSON::LD
  ##
  # A JSON-LD parser in Ruby.
  #
  # @see http://json-ld.org/spec/ED/20110507/
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class Reader < RDF::Reader
    format Format
    
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
      # the key `@iri` asserts that all vocabulary terms listed should undergo coercion to an IRI,
      # including `@base` processing for relative IRIs and CURIE processing for compact URI Expressions like
      # `foaf:homepage`.
      #
      # As the value may be an array, this is maintained as a reverse mapping of `property` => `type`.
      #
      # @attr [Hash{String => String}]
      attr :coerce

      # List coercion
      #
      # The @list keyword is used to specify that properties having an array value are to be treated
      # as an ordered list, rather than a normal unordered list
      # @attr [Array<String>]
      attr :list

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
        @list = []
        yield(self) if block_given?
      end

      def inspect
        v = %w([EvaluationContext) + %w(base vocab).map {|a| "#{a}='#{self.send(a).inspect}'"}
        v << "mappings[#{mappings.keys.length}]=#{mappings}"
        v << "coerce[#{coerce.keys.length}]=#{coerce}"
        v << "list[#{list.length}]=#{list}"
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
    # @raise [RDF::ReaderError] if the JSON document cannot be loaded
    def initialize(input = $stdin, options = {}, &block)
      super do
        @base_uri = uri(options[:base_uri]) if options[:base_uri]
        begin
          @doc = JSON.load(input)
        rescue JSON::ParserError => e
          raise RDF::ReaderError, "Failed to parse input document: #{e.message}"
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
      @callback = block

      # initialize the evaluation context with the appropriate base
      ec = EvaluationContext.new do |e|
        e.base = @base_uri if @base_uri
        parse_context(e, DEFAULT_CONTEXT)
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
        if element[CONTEXT]
          # Merge context
          ec = parse_context(ec.dup, element[CONTEXT])
          prefixes.merge!(ec.mappings)  # Update parsed prefixes
        end
        
        # 2.2) Create a new associative array by mapping the keys from the current associative array ...
        new_element = {}
        element.each do |k, v|
          k = ec.mappings[k.to_sym] while ec.mappings.has_key?(k.to_sym)
          new_element[k] = v
        end
        unless element == new_element
          add_debug(path, "traverse: keys after map: #{new_element.keys.inspect}")
          element = new_element
        end

        # Other shortcuts to allow use of this method for terminal associative arrays
        if element[IRI].is_a?(String)
          # 2.3 Return the IRI found from the value
          object = expand_term(element[IRI], ec.base, ec)
          add_triple(path, subject, property, object) if subject && property
          return
        elsif element[LITERAL]
          # 2.4
          literal_opts = {}
          literal_opts[:datatype] = expand_term(element[DATATYPE], ec.vocab.to_s, ec) if element[DATATYPE]
          literal_opts[:language] = element[LANGUAGE].to_sym if element[LANGUAGE]
          object = RDF::Literal.new(element[LITERAL], literal_opts)
          add_triple(path, subject, property, object) if subject && property
          return
        elsif element[LIST]
          # 2.4a (Lists)
          parse_list("#{path}[#{LIST}]", element[LIST], subject, property, ec)
          return
        elsif element[SUBJECT].is_a?(String)
          # 2.5 Subject
          # 2.5.1 Set active object (subject)
          active_subject = expand_term(element[SUBJECT], ec.base, ec)
        elsif element[SUBJECT]
          # 2.5.2 Recursively process hash or Array values
          traverse("#{path}[#{SUBJECT}]", element[SUBJECT], subject, property, ec)
        else
          # 2.6) Generate a blank node identifier and set it as the active subject.
          active_subject = RDF::Node.new
        end

        add_triple(path, subject, property, active_subject) if subject && property
        subject = active_subject
        
        element.each do |key, value|
          # 2.7) If a key that is not @context, @subject, or @type, set the active property by
          # performing Property Processing on the key.
          property = case key
          when TYPE then TYPE
          when /^@/ then next
          else      expand_term(key, ec.vocab, ec)
          end

          # 2.7.3
          if ec.list.include?(property.to_s) && value.is_a?(Array)
            # 2.7.3.1 (Lists) If the active property is the target of a @list coercion, and the value is an array,
            #         process the value as a list starting at Step 3a.
            parse_list("#{path}[#{key}]", value, subject, property, ec)
          else
            traverse("#{path}[#{key}]", value, subject, property, ec)
          end
        end
      when Array
        # 3) If a regular array is detected, process each value in the array by doing the following:
        element.each_with_index do |v, i|
          traverse("#{path}[#{i}]", v, subject, property, ec)
        end
      when String
        # Perform coersion of the value, or generate a literal
        add_debug(path, "traverse(#{element}): coerce?(#{property.inspect}) == #{ec.coerce[property.to_s].inspect}, ec=#{ec.coerce.inspect}")
        object = if ec.coerce[property.to_s] == IRI
          expand_term(element, ec.base, ec)
        elsif ec.coerce[property.to_s]
          RDF::Literal.new(element, :datatype => ec.coerce[property.to_s])
        else
          RDF::Literal.new(element)
        end
        property = RDF.type if property == TYPE
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
    # @param [Hash{String => String,Hash}, String] context
    #   JSON representation of @context
    # @return [EvaluationContext]
    # @raise [RDF::ReaderError]
    #   on a remote context load error, syntax error, or a reference to a term which is not defined.
    def parse_context(ec, context)
      # Load context document, if it is a string
      if context.is_a?(String)
        begin
          context = open(context.to_s) {|f| JSON.load(f)}
        rescue JSON::ParserError => e
          raise RDF::ReaderError, "Failed to parse remote context at #{context}: #{e.message}"
        end
      end
      
      context.each do |key, value|
        add_debug("parse_context(#{key})", value.inspect)
        case key
        when VOCAB then ec.vocab = value
        when BASE  then ec.base  = uri(value)
        when COERCE
          # Process after prefix mapping
        else
          # Spec confusion: The text indicates to merge each key-value pair into the active context. Is any
          # processing performed on the values. For instance, could a value be a CURIE, or {"@iri": <value>}?
          # Examples indicate that there is no such processing, and each value should be an absolute IRI. The
          # wording makes this unclear.
          ec.mappings[key.to_sym] = value
        end
      end
      
      if context[COERCE]
        # Spec confusion: doc says to merge each key-value mapping to the local context's @coerce mapping,
        # overwriting duplicate values. In the case where a mapping is indicated to a list of properties
        # (e.g., { "@iri": ["foaf:homepage", "foaf:member"] }, does this overwrite a previous mapping
        # of { "@iri": "foaf:knows" }, or add to it.
        add_error RDF::ReaderError, "Expected @coerce to reference an associative array" unless context[COERCE].is_a?(Hash)
        context[COERCE].each do |type, property|
          add_debug("parse_context: @coerce", "type=#{type}, prop=#{property}")
          type_uri = expand_term(type, ec.vocab, ec).to_s
          [property].flatten.compact.each do |prop|
            p = expand_term(prop, ec.vocab, ec).to_s
            if type == LIST
              # List is managed separate from types, as it is maintained in normal form.
              ec.list << p unless ec.list.include?(p)
            else
              ec.coerce[p] = type_uri
            end
          end
        end
      end

      ec
    end

    ##
    # Parse a List
    #
    # @param [String] path
    #   location within JSON hash
    # @param [Array] list
    #   The Array to serialize as a list
    # @param [RDF::URI] subject
    #   Inherited subject
    # @param [RDF::URI] property
    #   Inherited property
    # @param [EvaluationContext] ec
    #   The active context
    def parse_list(path, list, subject, property, ec)
      add_debug(path, "list: #{list.inspect}, s=#{subject.inspect}, p=#{property.inspect}, e=#{ec.inspect}")

      last = list.pop
      first_bnode = last ? RDF::Node.new : RDF.nil            
      add_triple("#{path}", subject, property, first_bnode)

      list.each do |list_item|
        traverse("#{path}", list_item, first_bnode, RDF.first, ec)
        rest_bnode = RDF::Node.new
        add_triple("#{path}", first_bnode, RDF.rest, rest_bnode)
        first_bnode = rest_bnode
      end
      if last
        traverse("#{path}", last, first_bnode, RDF.first, ec)
        add_triple("#{path}", first_bnode, RDF.rest, RDF.nil)
      end
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

