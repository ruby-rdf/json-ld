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
      # @attr [Hash{String => String}]
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
      # key is a String representation of the property for which String values will be coerced and
      # the value is the datatype (or @iri) to coerce to. Type coersion for
      # the value `@iri` asserts that all vocabulary terms listed should undergo coercion to an IRI,
      # including `@base` processing for relative IRIs and CURIE processing for compact IRI Expressions like
      # `foaf:homepage`.
      #
      # @attr [Hash{String => String}]
      attr :coerce, true

      # List coercion
      #
      # The @list keyword is used to specify that properties having an array value are to be treated
      # as an ordered list, rather than a normal unordered list
      # @attr [Array<String>]
      attr :list, true
      
      # Default language
      #
      # This adds a language to plain strings that aren't otherwise coerced
      # @attrs [Symbol]
      attr :language, true

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
      
      def dup
        # Also duplicate mappings, coerce and list
        ec = super
        ec.mappings = mappings.dup
        ec.coerce = coerce.dup
        ec.list = list.dup
        ec
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
          raise RDF::ReaderError, "Failed to parse input document: #{e.message}" if validate?
          @doc = JSON.parse("{}")
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
    # @return [RDF::Resource] defined by this element
    # @yield :resource
    # @yieldparam [RDF::Resource] :resource
    def traverse(path, element, subject, property, ec)
      add_debug(path) {"traverse: s=#{subject.inspect}, p=#{property.inspect}, e=#{ec.inspect}"}

      traverse_result = case element
      when Hash
        # 2.1) If a @context keyword is found, the processor merges each key-value pair in
        # the local context into the active context ...
        if element['@context']
          # Merge context
          ec = parse_context("#{path}[@context]", ec, element['@context'])
        end
        
        # 2.2) Create a new associative array by mapping the keys from the current associative array ...
        new_element = {}
        element.each do |k, v|
          k = ec.mappings[k.to_s] if ec.mappings[k.to_s].to_s[0,1] == '@'
          new_element[k] = v
        end
        unless element == new_element
          add_debug(path) {"traverse: keys after map: #{new_element.keys.inspect}"}
          element = new_element
        end

        # Other shortcuts to allow use of this method for terminal associative arrays
        object = if element['@iri'].is_a?(String)
          # 2.3 Return the IRI found from the value
          expand_term(element['@iri'], ec.base, ec)
        elsif element['@literal']
          # 2.4
          literal_opts = {}
          literal_opts[:datatype] = expand_term(element['@datatype'], ec.vocab.to_s, ec) if element['@datatype']
          literal_opts[:language] = element['@language'].to_sym if element['@language']
          RDF::Literal.new(element['@literal'], literal_opts)
        elsif element['@list']
          # 2.5 (Lists)
          parse_list("#{path}[#{'@list'}]", element['@list'], subject, property, ec) do |resource|
            add_triple(path, subject, property, resource) if subject && property
          end
        end

        if object
          yield object if block_given?
          return object
        end
        
        active_subject = if element['@subject'].is_a?(String)
          # 2.6 Subject
          # 2.6.1 Set active object (subject)
          expand_term(element['@subject'], ec.base, ec)
        elsif element['@subject']
          # 2.6.2 Recursively process hash or Array values
          traverse("#{path}[#{'@subject'}]", element['@subject'], subject, property, ec) do |resource|
            add_triple(path, subject, property, resource) if subject && property
          end
        else
          # 2.7) Generate a blank node identifier and set it as the active subject.
          RDF::Node.new
        end

        subject = active_subject
        
        element.each do |key, value|
          # 2.8.1) If a key that is not @context, @subject, or @type, set the active property by
          # performing Property Processing on the key.
          property = case key
          when '@type' then '@type'
          when /^@/ then next
          else      expand_term(key, ec.vocab, ec)
          end

          # 2.8.3
          object = if ec.list.include?(property.to_s) && value.is_a?(Array)
            # 2.8.3.1 (Lists) If the active property is the target of a @list coercion, and the value is an array,
            #         process the value as a list starting at Step 3a.
            parse_list("#{path}[#{key}]", value, subject, property, ec) do |resource|
              # Adds triple for head BNode only, the rest of the list is done within the method
              add_triple(path, subject, property, resource) if subject && property
            end
          else
            traverse("#{path}[#{key}]", value, subject, property, ec) do |resource|
              # Adds triples for each value
              add_triple(path, subject, property, resource) if subject && property
            end
          end
        end
        
        # The subject is returned
        subject
      when Array
        # 3) If a regular array is detected, process each value in the array by doing the following:
        element.each_with_index do |v, i|
          traverse("#{path}[#{i}]", v, subject, property, ec) do |resource|
            add_triple(path, subject, property, resource) if subject && property
          end
        end
        nil # No real value returned from an array
      when String
        # Perform coersion of the value, or generate a literal
        add_debug(path) do
          "traverse(#{element}): coerce?(#{property.inspect}) == #{ec.coerce[property.to_s].inspect}, " +
          "ec=#{ec.coerce.inspect}"
        end
        if ec.coerce[property.to_s] == '@iri'
          expand_term(element, ec.base, ec)
        elsif property == '@type'
          # @type value is an IRI resolved relative to @vocab, or a term/prefix
          property = RDF.type
          expand_term(element, ec.vocab, ec)
        elsif ec.coerce[property.to_s]
          RDF::Literal.new(element, :datatype => ec.coerce[property.to_s])
        else
          RDF::Literal.new(element, :language => ec.language)
        end
      when Float
        object = RDF::Literal::Double.new(element)
        add_debug(path) {"traverse(#{element}): native: #{object.inspect}"}
        object
      when Fixnum
        object = RDF::Literal.new(element)
        add_debug(path) {"traverse(#{element}): native: #{object.inspect}"}
        object
      when TrueClass, FalseClass
        object = RDF::Literal::Boolean.new(element)
        add_debug(path) {"traverse(#{element}): native: #{object.inspect}"}
        object
      else
        raise RDF::ReaderError, "Traverse to unknown element: #{element.inspect} of type #{element.class}"
      end
      
      # Yield and return traverse_result
      yield traverse_result if traverse_result && block_given?
      traverse_result
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
    # @return [RDF::Resource] BNode or nil for head of list
    # @yield :resource
    #   BNode or nil for head of list
    # @yieldparam [RDF::Resource] :resource
    def parse_list(path, list, subject, property, ec)
      add_debug(path) {"list: #{list.inspect}, s=#{subject.inspect}, p=#{property.inspect}, e=#{ec.inspect}"}

      last = list.pop
      result = first_bnode = last ? RDF::Node.new : RDF.nil

      list.each do |list_item|
        # Traverse the value, using _property_, not rdf:first, to ensure that
        # proper type coercion is performed
        traverse("#{path}", list_item, first_bnode, property, ec) do |resource|
          add_triple("#{path}", first_bnode, RDF.first, resource)
        end
        rest_bnode = RDF::Node.new
        add_triple("#{path}", first_bnode, RDF.rest, rest_bnode)
        first_bnode = rest_bnode
      end
      if last
        traverse("#{path}", last, first_bnode, property, ec) do |resource|
          add_triple("#{path}", first_bnode, RDF.first, resource)
        end
        add_triple("#{path}", first_bnode, RDF.rest, RDF.nil)
      end
      
      yield result if block_given?
      result
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
      predicate = RDF.type if predicate == '@type'
      statement = RDF::Statement.new(subject, predicate, object)
      add_debug(path) {"statement: #{statement.to_ntriples}"}
      @callback.call(statement)
    end

    ##
    # Add debug event to debug array, if specified
    #
    # @param [XML Node, any] node:: XML Node or string for showing context
    # @param [String] message
    # @yieldreturn [String] appended to message, to allow for lazy-evaulation of message
    def add_debug(node, message = "")
      return unless ::JSON::LD.debug? || @options[:debug]
      message = message + yield if block_given?
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
    def parse_context(path, ec, context)
      case context
      when String
        add_debug("#{path}parse_context", "remote: #{context}")
        # Load context document, if it is a string
        ctx = begin
          open(context.to_s) {|f| JSON.load(f)}
        rescue JSON::ParserError => e
          raise RDF::ReaderError, "Failed to parse remote context at #{context}: #{e.message}" if validate?
        end
        if ctx.is_a?(Hash) && ctx["@context"]
          parse_context(path, ec, ctx["@context"])
        else
          raise RDF::ReaderError, "Failed to retrieve @context from remote document at #{context}: #{e.message}" if validate?
        end
      when Array
        # Process each member of the array in order, updating the active context
        # Updates evaluation context serially during parsing
        add_debug("#{path}parse_context", "Array")
        context.each {|c| ec = parse_context(path, ec, c)}
        ec
      when Hash
        new_ec = ec.dup
        context.each do |key, value|
          # Expand a string value, unless it matches a keyword
          value = expand_term(value, ec.base, ec) if value.is_a?(String) && value[0,1] != '@'
          add_debug("#{path}parse_context(#{key})") {value.inspect}
          case key
          when '@vocab'    then new_ec.vocab = value.to_s
          when '@base'     then new_ec.base  = uri(value)
          when '@language' then new_ec.language = value.to_s.to_sym
          when '@coerce'
            # Process after prefix mapping.
            # FIXME: deprectaed
          else
            # If value is a Hash process contents
            case value
            when Hash
              if key.match(NC_REGEXP) || key.empty?
                # It defines a term, look up @iri, or do vocab expansion
                # Given @iri, expand it, otherwise resolve key relative to @vocab
                new_ec.mappings[key] = if value["@iri"]
                  expand_term(value["@iri"], ec.base, ec)
                else
                  # Expand term using vocab
                  expand_term(key, ec.vocab, ec)
                end
              
                prop = new_ec.mappings[key].to_s

                add_debug("#{path}parse_context") {"Term definition #{key} => #{prop.inspect}"}
              else
                # It is not a term definition, and must be a prefix:suffix or IRI
                prop = expand_term(key, ec.vocab, ec).to_s
                add_debug("#{path}parse_context") {"No term definition #{key} => #{prop.inspect}"}
              end

              # List inclusion
              if value["@list"]
                new_ec.list << prop unless new_ec.list.include?(prop)
              end

              # Coercion
              case value["@coerce"]
              when Array
                # With an array, there can be two items, one of which must be @list
                if value["@coerce"].include?(@list)
                  dtl = value["@coerce"] - "@list"
                  raise RDF::ReaderError,
                    "Coerce array for #{key} must only contain @list and a datatype: #{value['@coerce'].inspect}" unless
                    dtl.length == 1
                  case dtl.first
                  when "@iri"
                    add_debug("#{path}parse_context: @coerce", "@iri")
                    new_ec.coerce[prop] = '@iri'
                  when String
                    dt = expand_term(dtl.first, ec.vocab, ec)
                    add_debug("#{path}parse_context: @coerce") {"dt=#{dt}"}
                    new_ec.coerce[prop] = dt
                  end
                elsif validate?
                  raise RDF::ReaderError, "Coerce array for #{key} must contain @list: #{value['@coerce'].inspect}"
                end
                new_ec.list << prop unless new_ec.list.include?(prop)
              when Hash
                # Must be of the form {"@list" => dt}
                case value["@coerce"]["@list"]
                when "@iri"
                  add_debug("#{path}parse_context: @coerce", "@iri")
                  new_ec.coerce[prop] = '@iri'
                when String
                  dt = expand_term(value["@coerce"]["@list"], ec.vocab, ec)
                  add_debug("#{path}parse_context: @coerce") {"dt=#{dt}"}
                  new_ec.coerce[prop] = dt
                when nil
                  raise RDF::ReaderError, "Unknown coerce hash for #{key}: #{value['@coerce'].inspect}" if validate?
                end
                new_ec.list << prop unless new_ec.list.include?(prop)
              when "@iri"
                add_debug("#{path}parse_context: @coerce", "@iri")
                new_ec.coerce[prop] = '@iri'
              when "@list"
                dt = expand_term(value["@coerce"], ec.vocab, ec)
                add_debug("#{path}parse_context: @coerce", "@list")
                new_ec.list << prop unless new_ec.list.include?(prop)
              when String
                dt = expand_term(value["@coerce"], ec.vocab, ec)
                add_debug("#{path}parse_context: @coerce") {"dt=#{dt}"}
                new_ec.coerce[prop] = dt
              end
            else
              # Given a string (or URI), us it
              new_ec.mappings[key] = value
            end
          end
        end
      
        if context['@coerce']
          # Spec confusion: doc says to merge each key-value mapping to the local context's @coerce mapping,
          # overwriting duplicate values. In the case where a mapping is indicated to a list of properties
          # (e.g., { "@iri": ["foaf:homepage", "foaf:member"] }, does this overwrite a previous mapping
          # of { "@iri": "foaf:knows" }, or add to it.
          add_error RDF::ReaderError, "Expected @coerce to reference an associative array" unless context['@coerce'].is_a?(Hash)
          context['@coerce'].each do |type, property|
            add_debug("#{path}parse_context: @coerce") {"type=#{type}, prop=#{property}"}
            type_uri = expand_term(type, new_ec.vocab, new_ec).to_s
            [property].flatten.compact.each do |prop|
              p = expand_term(prop, new_ec.vocab, new_ec).to_s
              if type == '@list'
                # List is managed separate from types, as it is maintained in normal form.
                new_ec.list << p unless new_ec.list.include?(p)
              else
                new_ec.coerce[p] = type_uri
              end
            end
          end
        end

        prefixes.merge!(new_ec.mappings)  # Update parsed prefixes
        new_ec
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
      #add_debug("expand_term", {"term=#{term.inspect}, base=#{base.inspect}, ec=#{ec.inspect}"}
      return term unless term.is_a?(String)
      prefix, suffix = term.split(":", 2)
      if prefix == '_'
        #add_debug("expand_term") { "bnode: #{term}"}
        bnode(suffix)
      elsif ec.mappings.has_key?(prefix)
        #add_debug("expand_term") { "prefix: #{prefix} => #{ec.mappings[prefix]} + #{suffix}"}
        uri(ec.mappings[prefix] + suffix.to_s)
      elsif base
        #add_debug("expand_term") { "base: #{base.inspect} + #{term}"}
        base.respond_to?(:join) ? base.join(term) : uri(base + term)
      elsif term.to_s[0,1] == "@"
        #add_debug("expand_term") { "keyword: #{term}"}
        term
      else
        #add_debug("expand_term") { "uri: #{term}"}
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
    #
    # Don't actually use the name provided, to prevent name alias issues.
    # @return [RDF::Node]
    def bnode(value = nil)
      @bnode_cache ||= {}
      @bnode_cache[value.to_s] ||= RDF::Node.new
    end
  end
end

