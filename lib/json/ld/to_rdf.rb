require 'rdf/nquads'

module JSON::LD
  module Triples
    include Utils

    ##
    #
    # @param [String] path
    #   location within JSON hash
    # @param [Hash, Array, String] element
    #   The current JSON element being processed
    # @param [RDF::Node] subject
    #   Inherited subject
    # @param [RDF::URI] property
    #   Inherited property
    # @param [RDF::Node] name
    #   Inherited inherited graph name
    # @return [RDF::Resource] defined by this element
    # @yield :statement
    # @yieldparam [RDF::Statement] :statement
    def statements(path, element, subject, property, name, &block)
      debug(path) {"statements: e=#{element.inspect}, s=#{subject.inspect}, p=#{property.inspect}, n=#{name.inspect}"}
      @node_seq = "jld_t0000" unless subject || property

      traverse_result = depth do
        case element
        when Hash
          # Other shortcuts to allow use of this method for terminal associative arrays
          object = if element.has_key?('@value')
            # 1.2) If the JSON object has a @value key, set the active object to a literal value as follows ...
            literal_opts = {}
            literal_opts[:datatype] = RDF::URI(element['@type']) if element['@type']
            literal_opts[:language] = element['@language'].to_sym if element['@language']
            RDF::Literal.new(element['@value'], literal_opts)
          elsif element.has_key?('@list')
            # 1.3 (Lists)
            parse_list("#{path}[#{'@list'}]", element['@list'], property, name, &block)
          end

          if object
            # 1.4
            add_quad(path, subject, property, object, name, &block) if subject && property
            return object
          end
        
          active_subject = if element.fetch('@id', nil).is_a?(String)
            # 1.5 Subject
            # 1.5.1 Set active object (subject)
            context.expand_iri(element['@id'], :quite => true)
          else
            # 1.6) Generate a blank node identifier and set it as the active subject.
            node
          end

          # 1.7) For each key in the JSON object that has not already been processed,
          # perform the following steps:
          element.each do |key, value|
            active_property = case key
            when '@type'
              # If the key is @type, set the active property to rdf:type.
              RDF.type
            when '@graph'
              # Otherwise, if property is @graph, process value algorithm recursively, using active subject
              # as graph name and null values for active subject and active property and then continue to
              # next property
              statements("#{path}[#{key}]", value, nil, nil, active_subject, &block)
              next
            when /^@/
              # Otherwise, if property is a keyword, skip this step.
              next
            else
              # 1.7.1) If a key that is not @id, @graph, or @type, set the active property by
              # performing Property Processing on the key.
              context.expand_iri(key, :quite => true)
            end

            debug("statements[Step 1.7.4]")
            statements("#{path}[#{key}]", value, active_subject, active_property, name, &block)
          end
        
          # 1.8) The active_subject is returned
          active_subject
        when Array
          # 2) If a regular array is detected ...
          debug("statements[Step 2]")
          element.each_with_index do |v, i|
            statements("#{path}[#{i}]", v, subject, property, name, &block)
          end
          nil # No real value returned from an array
        when String
          object = RDF::Literal.new(element)
          debug(path) {"statements[Step 3]: plain: #{object.inspect}"}
          object
        when Float
          object = RDF::Literal::Double.new(element)
          debug(path) {"statements[Step 4]: native: #{object.inspect}"}
          object
        when Fixnum
          object = RDF::Literal.new(element)
          debug(path) {"statements[Step 5]: native: #{object.inspect}"}
          object
        when TrueClass, FalseClass
          object = RDF::Literal::Boolean.new(element)
          debug(path) {"statements[Step 6]: native: #{object.inspect}"}
          object
        else
          raise RDF::ReaderError, "Traverse to unknown element: #{element.inspect} of type #{element.class}"
        end
      end

      # Yield and return traverse_result
      add_quad(path, subject, property, traverse_result, name, &block) if subject && property && traverse_result
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
    # @param [RDF::Resource] name
    #   Inherited named graph context
    # @param [EvaluationContext] ec
    #   The active context
    # @return [RDF::Resource] BNode or nil for head of list
    # @yield :statement
    # @yieldparam [RDF::Statement] :statement
    def parse_list(path, list, property, name, &block)
      debug(path) {"list: #{list.inspect}, p=#{property.inspect}, n=#{name.inspect}"}

      last = list.pop
      result = first_bnode = last ? node : RDF.nil

      depth do
        list.each do |list_item|
          # Traverse the value
          statements("#{path}", list_item, first_bnode, RDF.first, name, &block)
          rest_bnode = node
          add_quad("#{path}", first_bnode, RDF.rest, rest_bnode, name, &block)
          first_bnode = rest_bnode
        end
        if last
          statements("#{path}", last, first_bnode, RDF.first, name, &block)
          add_quad("#{path}", first_bnode, RDF.rest, RDF.nil, name, &block)
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
    # @param [RDF::Resource] subject the subject of the statement
    # @param [RDF::URI] predicate the predicate of the statement
    # @param [RDF::Term] object the object of the statement
    # @param [RDF::Resource] name the named graph context of the statement
    # @yield :statement
    # @yieldParams [RDF::Statement] :statement
    def add_quad(path, subject, predicate, object, name)
      predicate = RDF.type if predicate == '@type'
      object = RDF::URI(object.to_s) if object.literal? && predicate == RDF.type
      statement = RDF::Statement.new(subject, predicate, object, :context => name)
      debug(path) {"statement: #{statement.to_nquads}"}
      yield statement
    end
  end
end
