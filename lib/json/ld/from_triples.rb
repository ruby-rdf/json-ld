require 'json/ld/utils'

module JSON::LD
  module FromTriples
    include Utils

    ##
    # Generate a JSON-LD array representation from an ordered array of RDF::Statement.
    #
    # @param [Array<RDF::Statement>] input
    # @param  [Hash{Symbol => Object}] options
    # @return [Array<Hash>] the JSON-LD document in normalized form
    def from_triples(input)
      array = []
      listMap = {}
      restMap = {}
      bnode_map = {}

      value = nil
      last_entry = nil
      ec = EvaluationContext.new

      # For each triple in input
      input.each do |statement|
        debug("statement") { statement.to_ntriples.chomp}

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

        # If the last entry in array is not a JSON Object with an @id having a value of subject:
        if !value.is_a?(Hash) || value['@id'] != subject
          debug("@id") { "new subject: #{subject}"}
          # Create a new JSON Object with key/value pair of @id and a string representation
          # of subject and use as value.
          value = Hash.ordered
          value['@id'] = subject
          last_entry = nil
          array << value
        end
        # Otherwise, set _value_ to the last element in _array_.
        
        # If property is http://www.w3.org/1999/02/22-rdf-syntax-ns#type:
        if statement.predicate == RDF.type
          object = ec.expand_iri(statement.object)
          debug("@type") { object.inspect}
          if last_entry == '@type' && value[last_entry].is_a?(Array)
            # If value has an key/value pair of @type and an array,
            # append the string representation of object to that array.
            value[last_entry] << object
          elsif last_entry == '@type'
            # Otherwise, if value has an key of @type, replace that value with a new array containing the
            # existing value and a string representation of object.
            value[last_entry] = [value[last_entry], object]
          else
            # Otherwise, create a new entry in value with a key of @type and value being a string representation of object.
            last_entry = '@type'
            value['@type'] = object
          end
        else
          # Let key be the string representation of predicate andlet object representation
          # be object represented in expanded form as described in Value Expansion.
          key = ec.expand_iri(statement.predicate).to_s
          object = ec.expand_value(key, statement.object)
          object_iri = object.fetch('@id', nil) if object.is_a?(Hash)

          debug("key/value") { "key: #{key}, :value #{object.inspect}"}
          
          # If object is http://www.w3.org/1999/02/22-rdf-syntax-ns#nil, replace
          # object representation with {"@list": []}
          object = {"@list" => []} if object_iri == RDF.nil.to_s

          # Non-normative, save a reference for the bnode to allow for easier list expansion
          bnode_map[object_iri] = {:obj => value, :key => key} if statement.object.is_a?(RDF::Node)
          
          if last_entry == key && value[last_entry].is_a?(Array)
            # If value has an key/value pair of key and an array, append object representation to that array.
            value[last_entry] << object
          elsif last_entry == key
            # Otherwise, if value has an key of key, replace that value with a new array containing the
            # existing value and object representation.
            value[last_entry] = [value[last_entry], object]
          else
            # Otherwise, create a new entry in value with a key of key and object representation.
            last_entry = key
            value[last_entry] = object
          end
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
