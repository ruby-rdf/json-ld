require 'rdf/nquads'

module JSON::LD
  module FromTriples
    include Utils

    ##
    # Generate a JSON-LD array representation from an array of `RDF::Statement`.
    # Representation is in expanded form
    #
    # @param [Array<RDF::Statement>] input
    # @param [BlankNodeNamer] namer
    # @return [Array<Hash>] the JSON-LD document in normalized form
    def from_statements(input, namer)
      array = []
      listMap = {}
      restMap = {}
      subjectMap = {}
      bnode_map = {}

      value = nil
      ec = EvaluationContext.new

      # Create a map for subject to object representation

      # For each triple in input
      input.each do |statement|
        debug("statement") { statement.to_nquads.chomp}

        subject = ec.expand_iri(statement.subject).to_s
        name = ec.expand_iri(statement.context).to_s if statement.context
        subject = namer.get_name(subject) if subject[0,2] == "_:"
        name = namer.get_name(name) if name.to_s[0,2] == "_:"

        case statement.predicate
        when RDF.first
          # If property is rdf:first,
          # create a new entry in _listMap_ for _name_ and _subject_ and an array value
          # containing the object representation and continue to the next statement.
          object_rep = ec.expand_value(nil, statement.object)
          object_rep['@id'] = namer.get_name(object_rep['@id']) if blank_node?(object_rep)
          debug("rdf:first") { "save object #{[object_rep].inspect}"}
          listMap[name] ||= {}
          listMap[name][subject] = [object_rep]
          next
        when RDF.rest
          # If property is rdf:rest,
          # and object is a blank node,
          # create a new entry in _restMap_ for _name_ and _subject_ and a value being the
          # result of IRI expansion on the object and continue to the next statement.
          next unless statement.object.is_a?(RDF::Node)
          object_rep = ec.expand_iri(statement.object).to_s
          object_rep = namer.get_name(object_rep) if object_rep[0,2] == '_:'
          debug("rdf:rest") { "save object #{object_rep.inspect}"}
          restMap[name] ||= {}
          restMap[name][subject] = object_rep
          next
        end

        # If name is not null
        if name
          # If _subjectMap_ does not have an entry for null as name and _name_ as subject
          subjectMap[nil] ||= {}
          value = subjectMap[nil][name]
          unless value
            # Create a new JSON Object with key/value pair of @id and a string representation
            # of name and append to array.
            debug("@id") { "new subject: #{name} for graph"}
            value = Hash.ordered
            value['@id'] = name
            array << (subjectMap[nil][name] = value)
          else
            # Otherwise, use that entry as value
          end

          # If value does not have an entry for @graph, initialize it as a new array
          a = value['@graph'] ||= []

          # If subjectMap does not have an entry for name and subject
          subjectMap[name] ||= {}
          value = subjectMap[name][subject]
          unless value
            # Create a new JSON Object with key/value pair of @id and a string representation
            # of name and append to the the graph array for name and use as value.
            debug("@id") { "new subject: #{subject} for graph: #{name}"}
            value = Hash.ordered
            value['@id'] = subject
            a << (subjectMap[name][subject] = value)
          else
            # Otherwise, use that entry as value
          end
        else
          # Otherwise, if subjectMap does not have an entry for _name_ and _subject_
          subjectMap[name] ||= {}
          value = subjectMap[nil][subject]
          unless value
            # Create a new JSON Object with key/value pair of @id and a string representation
            # of subject and append to array.
            debug("@id") { "new subject: #{subject}"}
            value = Hash.ordered
            value['@id'] = subject
            array << (subjectMap[nil][subject] = value)
          else
            # Otherwise, use that entry as value
          end
        end
        
        # If property is http://www.w3.org/1999/02/22-rdf-syntax-ns#type
        # and the notType option is not true
        if statement.predicate == RDF.type && !@options[:notType]
          object = ec.expand_iri(statement.object).to_s
          debug("@type") { object.inspect}
          # append the string representation of object to the array value for the key @type, creating
          # an entry if necessary
          (value['@type'] ||= []) << object
        elsif statement.object == RDF.nil
          # Otherwise, if object is http://www.w3.org/1999/02/22-rdf-syntax-ns#nil, let
          # key be the string representation of predicate. Set the value
          # for key to an empty @list representation {"@list": []}
          key = ec.expand_iri(statement.predicate).to_s
          value[key] = {"@list" => []}
        else
          # Otherwise, let key be the string representation of predicate and let object representation
          # be object represented in expanded form as described in Value Expansion.
          key = ec.expand_iri(statement.predicate).to_s
          object = ec.expand_value(key, statement.object)
          debug("object") {"detected that #{object.inspect} is a blank node"}
          object['@id'] = object_iri = namer.get_name(object['@id']) if blank_node?(object)

          debug("key/value") { "key: #{key}, :value #{object.inspect}"}
          
          # Non-normative, save a reference for the bnode to allow for easier list expansion
          bnode_map[object_iri] = {:obj => value, :key => key} if statement.object.is_a?(RDF::Node)

          # append the object object representation to the array value for key, creating
          # an entry if necessary
          (value[key] ||= []) << object
        end
      end

      # For each key/value _prev_, _rest_ entry in _restMap_, append to the _listMap_ value identified
      # by _prev_ the _listMap_ value identified by _rest_
      debug("restMap") {restMap.inspect}
      restMap.each do |gname, map|
        map.each do |prev, rest|
          debug("@list") { "Fold #{rest} into #{prev}"}
          listMap[gname][prev] += listMap[gname][rest]
        end
      end

      # For each key/value _node_, _list_, in _listMap_ where _list_ exists as a value of an object in _array_,
      # replace the object value with _list_
      debug("listMap") {listMap.inspect}
      listMap.each do |gname, map|
        map.each do |node, list|
          next unless bnode_map.has_key?(node)
          debug("@list") { "Replace #{bnode_map[node][:obj][bnode_map[node][:key]]} with #{listMap[node]}"}
          bnode_map[node][:obj][bnode_map[node][:key]] = {"@list" => listMap[gname][node]}
        end
      end

      # Return array as the graph representation.
      debug("fromRdf") {array.to_json(JSON_STATE)}
      array
    end
  end
end
