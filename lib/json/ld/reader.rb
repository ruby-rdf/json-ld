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
        @base_uri = RDF::URI(options[:base_uri]) if options[:base_uri]
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
      ec = EvaluationContext.new(@options) do |e|
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
      debug(path) {"traverse: s=#{subject.inspect}, p=#{property.inspect}, e=#{ec.inspect}"}

      traverse_result = case element
      when Hash
        # 2.1) If a @context keyword is found, the processor merges each key-value pair in
        # the local context into the active context ...
        if element['@context']
          # Merge context
          ec = ec.parse(element['@context']) {|block| debug("#{path}[@context]", &block)}
          prefixes.merge!(ec.mappings)  # Update parsed prefixes
        end
        
        # 2.2) Create a new associative array by mapping the keys from the current associative array ...
        new_element = {}
        element.each do |k, v|
          k = ec.mappings[k.to_s] if ec.mappings[k.to_s].to_s[0,1] == '@'
          new_element[k] = v
        end
        unless element == new_element
          debug(path) {"traverse: keys after map: #{new_element.keys.inspect}"}
          element = new_element
        end

        # Other shortcuts to allow use of this method for terminal associative arrays
        object = if element['@iri'].is_a?(String)
          # 2.3 Return the IRI found from the value
          ec.expand_base(element['@iri'])
        elsif element['@literal']
          # 2.4
          literal_opts = {}
          literal_opts[:datatype] = ec.expand_vocab(element['@datatype']) if element['@datatype']
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
          ec.expand_base(element['@subject'])
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
          else      ec.expand_vocab(key)
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
        debug(path) do
          "traverse(#{element}): coerce?(#{property.inspect}) == #{ec.coerce[property.to_s].inspect}, " +
          "ec=#{ec.coerce.inspect}"
        end
        if ec.coerce[property.to_s] == '@iri'
          ec.expand_base(element)
        elsif property == '@type'
          # @type value is an IRI resolved relative to @vocab, or a term/prefix
          property = RDF.type
          ec.expand_vocab(element)
        elsif ec.coerce[property.to_s]
          RDF::Literal.new(element, :datatype => ec.coerce[property.to_s])
        else
          RDF::Literal.new(element, :language => ec.language)
        end
      when Float
        object = RDF::Literal::Double.new(element)
        debug(path) {"traverse(#{element}): native: #{object.inspect}"}
        object
      when Fixnum
        object = RDF::Literal.new(element)
        debug(path) {"traverse(#{element}): native: #{object.inspect}"}
        object
      when TrueClass, FalseClass
        object = RDF::Literal::Boolean.new(element)
        debug(path) {"traverse(#{element}): native: #{object.inspect}"}
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
      debug(path) {"list: #{list.inspect}, s=#{subject.inspect}, p=#{property.inspect}, e=#{ec.inspect}"}

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
      debug(path) {"statement: #{statement.to_ntriples}"}
      @callback.call(statement)
    end

    ##
    # Add debug event to debug array, if specified
    #
    # @param [XML Node, any] node:: XML Node or string for showing context
    # @param [String] message
    # @yieldreturn [String] appended to message, to allow for lazy-evaulation of message
    def debug(node, message = "")
      return unless ::JSON::LD.debug? || @options[:debug]
      message = message + yield if block_given?
      puts "#{node}: #{message}" if JSON::LD::debug?
      @options[:debug] << "#{node}: #{message}" if @options[:debug].is_a?(Array)
    end
  end
end

