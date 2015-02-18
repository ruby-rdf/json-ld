require 'rdf'
require 'rdf/nquads'

module JSON::LD
  module ToRDF
    include Utils

    ##
    #
    # @param [Hash{String => Hash}] active_graph
    #   A hash of IRI to Node definitions
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    def graph_to_rdf(active_graph, &block)
      debug('graph_to_rdf') {"graph_to_rdf: #{active_graph.inspect}"}

      # For each id-node in active_graph
      active_graph.each do |id, node|
        # Initialize subject as the IRI or BNode representation of id
        subject = as_resource(id)
        debug("graph_to_rdf")  {"subject: #{subject.to_ntriples rescue 'malformed rdf'} (id: #{id})"}

        # For each property-values in node
        node.each do |property, values|
          case property
          when '@type'
            # If property is @type, construct triple as an RDF Triple composed of id, rdf:type, and object from values where id and object are represented either as IRIs or Blank Nodes
            values.each do |value|
              object = as_resource(value)
              debug("graph_to_rdf")  {"type: #{object.to_ntriples rescue 'malformed rdf'}"}
              yield RDF::Statement.new(subject, RDF.type, object)
            end
          when /^@/
            # Otherwise, if @type is any other keyword, skip to the next property-values pair
          else
            # Otherwise, property is an IRI or Blank Node identifier
            # Initialize predicate from  property as an IRI or Blank node
            predicate = as_resource(property)
            debug("graph_to_rdf")  {"predicate: #{predicate.to_ntriples rescue 'malformed rdf'}"}

            # For each item in values
            values.each do |item|
              if item.has_key?('@list')
                debug("graph_to_rdf")  {"list: #{item.inspect}"}
                # If item is a list object, initialize list_results as an empty array, and object to the result of the List Conversion algorithm, passing the value associated with the @list key from item and list_results.
                object = parse_list(item['@list']) {|stmt| yield stmt}

                # Append a triple composed of subject, prediate, and object to results and add all triples from list_results to results.
                yield RDF::Statement.new(subject, predicate, object)
              else
                # Otherwise, item is a value object or a node definition. Generate object as the result of the Object Converstion algorithm passing item.
                object = parse_object(item)
                debug("graph_to_rdf")  {"object: #{object.to_ntriples rescue 'malformed rdf'}"}
                # Append a triple composed of subject, prediate, and literal to results.
                yield RDF::Statement.new(subject, predicate, object)
              end
            end
          end
        end
      end
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
          lit = RDF::Literal.new(value, canonicalize: true)
          value = lit.to_s
          datatype ||= lit.datatype
        else
          # Otherwise, if datatype is null, set it to xsd:string or xsd:langString, depending on if item has a @language key.
          datatype ||= item.has_key?('@language') ? RDF.langString : RDF::XSD.string
        end
        datatype = RDF::URI(datatype) if datatype && !datatype.is_a?(RDF::URI)
                  
        # Initialize literal as an RDF literal using value and datatype. If element has the key @language and datatype is xsd:string, then add the value associated with the @language key as the language of the object.
        language = item.fetch('@language', nil)
        RDF::Literal.new(value, datatype: datatype, language: language)
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
    # @yield statement
    # @yieldparam [RDF::Resource] statement
    # @return [Array<RDF::Statement>]
    #   Statements for each item in the list
    def parse_list(list)
      debug('parse_list') {"list: #{list.inspect}"}

      last = list.pop
      result = first_bnode = last ? node : RDF.nil

      list.each do |list_item|
        # Set first to the result of the Object Converstion algorithm passing item.
        object = parse_object(list_item)
        yield RDF::Statement.new(first_bnode, RDF.first, object)
        rest_bnode = node
        yield RDF::Statement.new(first_bnode, RDF.rest, rest_bnode)
        first_bnode = rest_bnode
      end
      if last
        object = parse_object(last)
        yield RDF::Statement.new(first_bnode, RDF.first, object)
        yield RDF::Statement.new(first_bnode, RDF.rest, RDF.nil)
      end
      result
    end

    ##
    # Create a new named node using the sequence
    def node
      RDF::Node.new(namer.get_sym)
    end
  end
end
