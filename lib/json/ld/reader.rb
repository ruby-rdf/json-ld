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

      # initialize the evaluation context with initial context
      ec = EvaluationContext.new(@options)

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
      debug(path) {"traverse: e=#{element.class.inspect}, s=#{subject.inspect}, p=#{property.inspect}, e=#{ec.inspect}"}

      traverse_result = case element
      when Hash
        # 2.1) If a @context keyword is found, the processor merges each key-value pair in
        # the local context into the active context ...
        if element['@context']
          # Merge context
          ec = ec.parse(element['@context'])
          prefixes.merge!(ec.mappings)  # Update parsed prefixes
        end
        
        # 2.2) Create a copy of the current JSON object, changing keys that map to JSON-LD keywords with those keywords.
        #      Use the new JSON object in subsequent steps
        new_element = {}
        element.each do |k, v|
          k = ec.mapping(k) if ec.mapping(k).to_s[0,1] == '@'
          new_element[k] = v
        end
        unless element == new_element
          debug(path) {"traverse: keys after map: #{new_element.keys.inspect}"}
          element = new_element
        end

        # Other shortcuts to allow use of this method for terminal associative arrays
        object = if element['@value']
          # 2.3) If the JSON object has a @value key, set the active object to a literal value as follows ...
          literal_opts = {}
          literal_opts[:datatype] = ec.expand_iri(element['@type'], :position => :datatype) if element['@type']
          literal_opts[:language] = element['@language'].to_sym if element['@language']
          RDF::Literal.new(element['@value'], literal_opts)
        elsif element['@list']
          # 2.4 (Lists)
          parse_list("#{path}[#{'@list'}]", element['@list'], property, ec) do |resource|
            add_triple(path, subject, property, resource) if subject && property
          end
        end

        if object
          yield object if block_given?
          return object
        end
        
        active_subject = if element['@id'].is_a?(String)
          # 2.5 Subject
          # 2.5.1 Set active object (subject)
          ec.expand_iri(element['@id'], :position => :subject)
        elsif element['@id']
          # 2.5.2 Recursively process hash or Array values
          traverse("#{path}[#{'@id'}]", element['@id'], subject, property, ec) do |resource|
            add_triple(path, subject, property, resource) if subject && property
          end
        else
          # 2.6) Generate a blank node identifier and set it as the active subject.
          RDF::Node.new
        end

        subject = active_subject
        
        # 2.7) For each key in the JSON object that has not already been processed, perform the following steps:
        element.each do |key, value|
          # 2.7.1) If a key that is not @context, @id, or @type, set the active property by
          # performing Property Processing on the key.
          property = case key
          when '@type' then RDF.type
          when /^@/ then next
          else      ec.expand_iri(key, :position => :predicate)
          end

          # 2.7.3) List expansion
          object = if ec.list(property) && value.is_a?(Array)
            # If the active property is the target of a @list coercion, and the value is an array,
            # process the value as a list starting at Step 3.1.
            parse_list("#{path}[#{key}]", value, property, ec) do |resource|
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
        
        # 2.8) The subject is returned
        subject
      when Array
        # 3) If a regular array is detected ...
        element.each_with_index do |v, i|
          traverse("#{path}[#{i}]", v, subject, property, ec) do |resource|
            add_triple(path, subject, property, resource) if subject && property
          end
        end
        nil # No real value returned from an array
      when String
        # 4) Perform coersion of the value, or generate a literal
        debug(path) do
          "traverse(#{element}): coerce(#{property.inspect}) == #{ec.coerce(property).inspect}, " +
          "ec=#{ec.coercions.inspect}"
        end
        if ec.coerce(property) == '@id'
          # 4.1) If the active property is the target of a @id coercion ...
          ec.expand_iri(element, :position => :object)
        elsif ec.coerce(property)
          # 4.2) Otherwise, if the active property is the target of coercion ..
          RDF::Literal.new(element, :datatype => ec.coerce(property))
        else
          # 4.3) Otherwise, set the active object to a plain literal value created from the string.
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
    # @param [RDF::URI] property
    #   Inherited property
    # @param [EvaluationContext] ec
    #   The active context
    # @return [RDF::Resource] BNode or nil for head of list
    # @yield :resource
    #   BNode or nil for head of list
    # @yieldparam [RDF::Resource] :resource
    def parse_list(path, list, property, ec)
      debug(path) {"list: #{list.inspect}, p=#{property.inspect}, e=#{ec.inspect}"}

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
    def debug(*args)
      return unless ::JSON::LD.debug? || @options[:debug]
      message = " " * (@depth || 0) * 2 + (args.empty? ? "" : args.join(": "))
      message += yield if block_given?
      puts message if JSON::LD::debug?
      @options[:debug] << message if @options[:debug].is_a?(Array)
    end
  end
end

