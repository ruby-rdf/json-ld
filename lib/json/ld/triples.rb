require 'json/ld/utils'

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
      debug(path) {"element: #{element.inspect}"} if path.empty? && subject.nil? && property.nil?
      debug(path) {"triples: e=#{element.class.inspect}, s=#{subject.inspect}, p=#{property.inspect}"}

      traverse_result = depth do
        case element
        when Hash
          # Other shortcuts to allow use of this method for terminal associative arrays
          object = if element['@value']
            # 2.3) If the JSON object has a @value key, set the active object to a literal value as follows ...
            literal_opts = {}
            literal_opts[:datatype] = RDF::URI(element['@type']) if element['@type']
            literal_opts[:language] = element['@language'].to_sym if element['@language']
            RDF::Literal.new(element['@value'], literal_opts)
          elsif element['@list']
            # 2.4 (Lists)
            parse_list("#{path}[#{'@list'}]", element['@list'], property, &block)
          end

          if object
            add_triple(path, subject, property, object, &block) if subject && property
            return object
          end
        
          active_subject = if element['@id'].is_a?(String)
            # 2.5 Subject
            # 2.5.1 Set active object (subject)
            context.expand_iri(element['@id'])
          elsif element['@id']
            # 2.5.2 Recursively process hash or Array values
            triples("#{path}[#{'@id'}]", element['@id'], subject, property, &block)
          else
            # 2.6) Generate a blank node identifier and set it as the active subject.
            RDF::Node.new
          end

          # 2.7) For each key in the JSON object that has not already been processed, perform the following steps:
          element.each do |key, value|
            # 2.7.1) If a key that is not @id, or @type, set the active property by
            # performing Property Processing on the key.
            active_property = case key
            when '@type' then RDF.type
            when /^@/ then next
            else      context.expand_iri(key)
            end

            triples("#{path}[#{key}]", value, active_subject, active_property, &block)
          end
        
          # 2.8) The active_subject is returned
          active_subject
        when Array
          # 3) If a regular array is detected ...
          element.each_with_index do |v, i|
            triples("#{path}[#{i}]", v, subject, property, &block)
          end
          nil # No real value returned from an array
        when String
          object = RDF::Literal.new(element)
          debug(path) {"triples(#{element}): plain: #{object.inspect}"}
          object
        when Float
          object = RDF::Literal::Double.new(element)
          debug(path) {"triples(#{element}): native: #{object.inspect}"}
          object
        when Fixnum
          object = RDF::Literal.new(element)
          debug(path) {"triples(#{element}): native: #{object.inspect}"}
          object
        when TrueClass, FalseClass
          object = RDF::Literal::Boolean.new(element)
          debug(path) {"triples(#{element}): native: #{object.inspect}"}
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
      result = first_bnode = last ? RDF::Node.new : RDF.nil

      depth do
        list.each do |list_item|
          # Traverse the value
          triples("#{path}", list_item, first_bnode, RDF.first, &block)
          rest_bnode = RDF::Node.new
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
