require 'rdf'
require 'rdf/nquads'

module JSON::LD
  module ToRDF
    include Utils

    ##
    #
    # @param [Hash{String => Hash}] activeGraph
    #   A hash of IRI to Node definitions
    # @return [Array<RDF::Statement>] statements in this graph, without context
    def graph_to_rdf(activeGraph)
      debug('graph_to_rdf') {"graph_to_rdf: #{activeGraph.inspect}"}

      # Initialize results as an empty array
      results = []

      depth do
        # For each id-node in activeGraph
        activeGraph.each do |id, node|
          # Initialize subject as the IRI or BNode representation of id
          subject = as_resource(id)
          debug("graph_to_rdf")  {"subject: #{subject.to_ntriples}"}

          # For each property-values in node
          node.each do |property, values|
            case property
            when '@type'
              # If property is @type, construct triple as an RDF Triple composed of id, rdf:type, and object from values where id and object are represented either as IRIs or Blank Nodes
              results += values.map do |value|
                object = as_resource(value)
                debug("graph_to_rdf")  {"type: #{object.to_ntriples}"}
                RDF::Statement.new(subject, RDF.type, object)
              end
            when /^@/
              # Otherwise, if @type is any other keyword, skip to the next property-values pair
            else
              # Otherwise, property is an IRI or Blank Node identifier
              # Initialize predicate from  property as an IRI or Blank node
              predicate = as_resource(property)
              debug("graph_to_rdf")  {"predicate: #{predicate.to_ntriples}"}

              # For each item in values
              values.each do |item|
                if item.has_key?('@list')
                  debug("graph_to_rdf")  {"list: #{item.inspect}"}
                  # If item is a list object, initialize list_results as an empty array, and object to the result of the List Conversion algorithm, passing the value associated with the @list key from item and list_results.
                  list_results = []
                  object = parse_list(item['@list'], list_results)

                  # Append a triple composed of subject, prediate, and object to results and add all triples from list_results to results.
                  results << RDF::Statement.new(subject, predicate, object)
                  results += list_results
                else
                  # Otherwise, item is a value object or a node definition. Generate object as the result of the Object Converstion algorithm passing item.
                  object = parse_object(item)
                  debug("graph_to_rdf")  {"object: #{object.to_ntriples}"}
                  # Append a triple composed of subject, prediate, and literal to results.
                  results << RDF::Statement.new(subject, predicate, object)
                end
              end
            end
          end
        end
      end
      
      # Return results
      results
    end

    ##
    # Parse an item, either a value object or a node definition
    # @param [Hash] item
    # @return [RDF::Value]
    def parse_object(item)
      if item.has_key?('@value')
        # Otherwise, if element is a JSON object that contains the key @value
        # Initialize value to the value associated with the @value key in element. Initialize datatype to the value associated with the @type key in element, or null if element does not contain that key.
        value, datatype = item.fetch('@value'), item.fetch('@type', nil)

        case value
        when TrueClass, FalseClass
          # If value is true or false, then set value its canonical lexical form as defined in the section Data Round Tripping. If datatype is null, set it to xsd:boolean.
          value = value.to_s
          datatype ||= RDF::XSD.boolean.to_s
        when Float, Fixnum
          # Otherwise, if value is a number, then set value to its canonical lexical form as defined in the section Data Round Tripping. If datatype is null, set it to either xsd:integer or xsd:double, depending on if the value contains a fractional and/or an exponential component.
          lit = RDF::Literal.new(value, :canonicalize => true)
          value = lit.to_s
          datatype ||= lit.datatype.to_s
        else
          # Otherwise, if datatype is null, set it to xsd:string or xsd:langString, depending on if item has a @language key.
          datatype ||= RDF::XSD.send(item.has_key?('@language') ? :langString : :string).to_s
        end
                  
        # Initialize literal as an RDF literal using value and datatype. If element has the key @language and datatype is xsd:string, then add the value associated with the @language key as the language of the object.
        language = item.fetch('@language', nil)
        literal = RDF::Literal.new(value, :datatype => datatype, :language => language)

        # Return literal
        literal
      else
        # Otherwise, value must be a node definition containing only @id whos value is an IRI or Blank Node identifier
        raise "Expected node reference, got #{item.inspect}" unless item.keys == %w(@id)
        # Return value associated with @id as an IRI or Blank node
        as_resource(item['@id'])
      end
    end

    ##
    # Parse a List
    #
    # @param [Array] list
    #   The Array to serialize as a list
    # @param [Array<RDF::Statement>] list_results
    #   Statements for each item in the list
    # @return [RDF::Resource] BNode or nil for head of list
    def parse_list(list, list_results)
      debug('parse_list') {"list: #{list.inspect}"}

      last = list.pop
      result = first_bnode = last ? node : RDF.nil

      depth do
        list.each do |list_item|
          # Set first to the result of the Object Converstion algorithm passing item.
          object = parse_object(list_item)
          list_results << RDF::Statement.new(first_bnode, RDF.first, object)
          rest_bnode = node
          list_results << RDF::Statement.new(first_bnode, RDF.rest, rest_bnode)
          first_bnode = rest_bnode
        end
        if last
          object = parse_object(last)
          list_results << RDF::Statement.new(first_bnode, RDF.first, object)
          list_results << RDF::Statement.new(first_bnode, RDF.rest, RDF.nil)
        end
      end
      result
    end

    ##
    # Create a new named node using the sequence
    def node
      RDF::Node.new(namer.get_sym)
    end

    ##
    # add a statement, object can be literal or URI or bnode
    #
    # @param [String] path
    # @param [RDF::Resource] subject the subject of the statement
    # @param [RDF::URI] predicate the predicate of the statement
    # @param [RDF::Term] object the object of the statement
    # @param [RDF::Resource] name the named graph context of the statement
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    def add_quad(path, subject, predicate, object, name)
      predicate = RDF.type if predicate == '@type'
      object = context.expand_iri(object.to_s, :quiet => true) if object.literal? && predicate == RDF.type
      statement = RDF::Statement.new(subject, predicate, object, :context => name)
      debug(path) {"statement: #{statement.to_nquads}"}
      yield statement
    end
  end
end
