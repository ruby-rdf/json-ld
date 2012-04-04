module JSON::LD
  module Triples
    include Utils

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
    # @return [RDF::Resource] defined by this element
    # @yield :statement
    # @yieldparam [RDF::Statement] :statement
    def triples(path, element, subject, property, &block)
      debug(path) {"triples: e=#{element.inspect}, s=#{subject.inspect}, p=#{property.inspect}"}
      @node_seq = "jld_t0000" unless subject || property

      traverse_result = depth do
        case element
        when Hash
          # Other shortcuts to allow use of this method for terminal associative arrays
          object = if element['@value']
            # 1.2) If the JSON object has a @value key, set the active object to a literal value as follows ...
            literal_opts = {}
            literal_opts[:datatype] = RDF::URI(element['@type']) if element['@type']
            literal_opts[:language] = element['@language'].to_sym if element['@language']
            RDF::Literal.new(element['@value'], literal_opts)
          elsif element['@list']
            # 1.3 (Lists)
            parse_list("#{path}[#{'@list'}]", element['@list'], property, &block)
          end

          if object
            # 1.4
            add_triple(path, subject, property, object, &block) if subject && property
            return object
          end
        
          active_subject = if element['@id'].is_a?(String)
            # 1.5 Subject
            # 1.5.1 Set active object (subject)
            context.expand_iri(element['@id'], :quite => true)
          elsif element['@graph']
            # 1.5.2 Recursively process hash or Array values
            debug("triples[Step 1.5.2]")
            triples("#{path}[#{'@graph'}]", element['@graph'], subject, property, &block)
          else
            # 1.6) Generate a blank node identifier and set it as the active subject.
            node
          end

          # 1.7) For each key in the JSON object that has not already been processed, perform the following steps:
          element.each do |key, value|
            # 1.7.1) If a key that is not @id, or @type, set the active property by
            # performing Property Processing on the key.
            active_property = case key
            when '@type' then RDF.type
            when /^@/ then next
            else      context.expand_iri(key, :quite => true)
            end

            debug("triples[Step 1.7.4]")
            triples("#{path}[#{key}]", value, active_subject, active_property, &block)
          end
        
          # 1.8) The active_subject is returned
          active_subject
        when Array
          # 2) If a regular array is detected ...
          debug("triples[Step 2]")
          element.each_with_index do |v, i|
            triples("#{path}[#{i}]", v, subject, property, &block)
          end
          nil # No real value returned from an array
        when String
          object = RDF::Literal.new(element)
          debug(path) {"triples[Step 3]: plain: #{object.inspect}"}
          object
        when Float
          object = RDF::Literal::Double.new(element)
          debug(path) {"triples[Step 4]: native: #{object.inspect}"}
          object
        when Fixnum
          object = RDF::Literal.new(element)
          debug(path) {"triples[Step 5]: native: #{object.inspect}"}
          object
        when TrueClass, FalseClass
          object = RDF::Literal::Boolean.new(element)
          debug(path) {"triples[Step 6]: native: #{object.inspect}"}
          object
        else
          raise RDF::ReaderError, "Traverse to unknown element: #{element.inspect} of type #{element.class}"
        end
      end

      # Yield and return traverse_result
      add_triple(path, subject, property, traverse_result, &block) if subject && property && traverse_result
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
    # @yield :statement
    # @yieldparam [RDF::Statement] :statement
    def parse_list(path, list, property, &block)
      debug(path) {"list: #{list.inspect}, p=#{property.inspect}"}

      last = list.pop
      result = first_bnode = last ? node : RDF.nil

      depth do
        list.each do |list_item|
          # Traverse the value
          triples("#{path}", list_item, first_bnode, RDF.first, &block)
          rest_bnode = node
          add_triple("#{path}", first_bnode, RDF.rest, rest_bnode, &block)
          first_bnode = rest_bnode
        end
        if last
          triples("#{path}", last, first_bnode, RDF.first, &block)
          add_triple("#{path}", first_bnode, RDF.rest, RDF.nil, &block)
        end
      end
      result
    end

    ##
    # Create a new named node using the sequence
    def node
      n = RDF::Node.new(@node_seq)
      @node_seq = @node_seq.succ
      n
    end

    ##
    # add a statement, object can be literal or URI or bnode
    #
    # @param [String] path
    # @param [URI, BNode] subject the subject of the statement
    # @param [URI] predicate the predicate of the statement
    # @param [URI, BNode, Literal] object the object of the statement
    # @yield :statement
    # @yieldParams [RDF::Statement] :statement
    def add_triple(path, subject, predicate, object)
      predicate = RDF.type if predicate == '@type'
      object = RDF::URI(object.to_s) if object.literal? && predicate == RDF.type
      statement = RDF::Statement.new(subject, predicate, object)
      debug(path) {"statement: #{statement.to_ntriples}"}
      yield statement
    end
  end
end
