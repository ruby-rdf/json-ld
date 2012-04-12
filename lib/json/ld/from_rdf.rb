require 'rdf/nquads'

module JSON::LD
  module FromTriples
    include Utils

    ##
    # Generate a JSON-LD array representation from an ordered array of RDF::Statement.
    # Representation is in expanded form
    #
    # @param [Array<RDF::Statement>] input
    # @param  [Hash{Symbol => Object}] options
    # @return [Array<Hash>] the JSON-LD document in normalized form
    def from_statements(input)
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

        case statement.predicate
        when RDF.first
          # If property is rdf:first,
          # create a new entry in _listMap_ with a key of _subject_ and an array value
          # containing the object representation and continue to the next statement.
          object_rep = ec.expand_value(nil, statement.object)
          debug("rdf:first") { "save object #{[object_rep].inspect}"}
          listMap[subject] = [object_rep]
          next
        when RDF.rest
          # If property is rdf:rest,
          # and object is a blank node,
          # create a new entry in _restMap_ with a key of _subject_ and a value being the
          # result of IRI expansion on the object and continue to the next statement.
          next unless statement.object.is_a?(RDF::Node)
          object_rep = ec.expand_iri(statement.object).to_s
          debug("rdf:rest") { "save object #{object_rep.inspect}"}
          restMap[subject] = object_rep
          next
        end

        # If _subjectMap_ does not have an entry for subject
        value = subjectMap[subject]
        unless value
          debug("@id") { "new subject: #{subject}"}
          # Create a new JSON Object with key/value pair of @id and a string representation
          # of subject and use as value.
          value = Hash.ordered
          value['@id'] = subject

          # Save value in _subjectMap_ for subject and append to _array_.
          array << (subjectMap[subject] = value)
        end
        # Otherwise, set _value_ to the value for subject in _subjectMap_.
        
        # If property is http://www.w3.org/1999/02/22-rdf-syntax-ns#type:
        if statement.predicate == RDF.type
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
          object_iri = object.fetch('@id', nil) if object.is_a?(Hash)

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
      restMap.each do |prev, rest|
        debug("@list") { "Fold #{rest} into #{prev}"}
        listMap[prev] += listMap[rest] rescue debug("Oh Fuck!")
      end

      # For each key/value _node_, _list_, in _listMap_ where _list_ exists as a value of an object in _array_,
      # replace the object value with _list_
      debug("listMap") {listMap.inspect}
      listMap.each do |node, list|
        next unless bnode_map.has_key?(node)
        debug("@list") { "Replace #{bnode_map[node][:obj][bnode_map[node][:key]]} with #{listMap[node]}"}
        bnode_map[node][:obj][bnode_map[node][:key]] = {"@list" => listMap[node]}
      end

      # Return array as the graph representation.
      array
    end
  end
end
