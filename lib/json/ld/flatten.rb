module JSON::LD
  module Flatten
    include Utils

    ##
    # Build hash of nodes used for framing. Also returns flattened representation of input.
    #
    # @param [Array, Hash] element
    #   Expanded element
    # @param [Hash{String => Hash}] nodeMap
    #   map of nodes
    # @param [String] active_graph
    #   Graph name for results
    # @param [Array] list
    #   List for saving list elements
    # @param [String] id (nil)
    #   Identifier already associated with element
    def generate_node_map(element,
                          nodeMap,
                          active_graph    = '@default',
                          active_subject  = nil,
                          active_property = nil,
                          list            = nil)
      depth do
        debug("nodeMap") {"active_graph: #{active_graph}, element: #{element.inspect}"}
        if element.is_a?(Array)
          # If element is an array, process each entry in element recursively, using this algorithm and return
          element.map {|o|
            generate_node_map(o,
                              nodeMap,
                              active_graph,
                              active_subject,
                              active_property,
                              list)
          }
        else
          # Otherwise element is a JSON object. Let activeGraph be the JSON object which is the value of the active graph member of nodeMap.
          # Spec FIXME: initializing it to an empty JSON object, if necessary
          raise "Expected element to be a hash, was #{element.class}" unless element.is_a?(Hash)
          activeGraph = nodeMap[active_graph] ||= Hash.ordered

          # If it has an @type member, perform for each item the following steps:
          # Spec FIXME: each item which is a value of @type
          [element['@type']].flatten.each do |item|
            # If item is a blank node identifier, replace it with a new blank node identifier.
            item = namer.get_name(item) if item[0,2] == '_:'

            # If activeGraph has no member item, create it and initialize its value to a JSON object consisting of a single member @id with the value item.
            activeGraph[item] ||= {'@id' => item}
          end if element.has_key?('@type')

          # If element has an @value member, perform the following steps:
          if element.has_key?('@value')
            unless list
              # If no list has been passed, merge element into the active property member of the active subject in activeGraph.
              merge_value(activeGraph[active_subject], active_property, element)
            else
              # Otherwise, append element to the @list member of list.
              merge_value(list, '@list', element)
            end
          elsif element.has_key?('@list')
            # Otherwise, if element has an @list member, perform the following steps:
            # Initialize a new JSON object result having a single member @list whose value is initialized to an empty array.
            result = {'@list' => []}

            # Recursively call this algorithm passing the value of element's @list member as new element and result as list.
            generate_node_map(element['@list'],
                              nodeMap,
                              active_graph,
                              active_subject,
                              active_property,
                              result)

            if (active_property || '@graph') == '@graph'
              # If active property equals null or @graph, generate a blank node identifier id and store result as value of the member id in activeGraph.
              # FIXME: Free-floating list, should be dropped
              activeGraph[namer.get_name] = result
            else
              # Otherwise, add result to the the value of the active property member of the active subject in activeGraph.
              merge_value(activeGraph[active_subject], active_property, result)
            end
          else
            # Otherwise element is a node object, perform the following steps:
          
            # If element has an @id member, store its value in id and remove the member from element. If id is a blank node identifier, replace it with a new blank node identifier.
            # Otherwise generate a new blank node identifier and store it as id.
            id = element.delete('@id')
            id = namer.get_name(id) if id.nil? || id[0,2] == '_:'
            debug("nodeMap") {"id: #{id.inspect}"}

            # If activeGraph does not contain a member id, create one and initialize it to a JSON object consisting of a single member @id whose value is set to id.
            activeGraph[id] ||= Hash.ordered
            activeGraph[id]['@id'] ||= id

            # If active property is not null, perform the following steps:
            if active_property
              # Create a new JSON object reference consisting of a single member @id whose value is id.
              reference = Hash.ordered
              reference['@id'] = id

              # If no list has been passed, merge element into the active property member of the active subject in activeGraph.
              unless list
                merge_value(activeGraph[active_subject], active_property, reference)
              else
                merge_value(list, '@list', reference)
              end
            end

            # If element has an @type member, merge each value into the @type of active subject in activeGraph. Then remove the @type member from element.
            # Spec FIXME: should be id, not active subject
            if element.has_key?('@type')
              [element.delete('@type')].flatten.each do |t|
                merge_value(activeGraph[id], '@type', t)
              end
            end

            # If element has an @index member, set the @index of active subject in activeGraph to its value. If such a member already exists in active subject and has a different value, raise a conflicting indexes error. Otherwise continue and remove the @index from element.
            if element.has_key?('@index')
              # FIXME: check for duplicates?
              activeGraph[active_subject]['@index'] = element.delete('@index')
            end

            # If element has an @graph member, recursively invoke this algorithm passing the value of the @graph member as new element and id as new active subject. Then remove the @graph member from element.
            # Spec FIXME: as active_graph, not active_subject
            # Spec FIXME: creating an entry in nodeMap for id initialized to an empty JSON Object if necessary
            if element.has_key?('@graph')
              generate_node_map(element.delete('@graph'),
                                nodeMap,
                                id)
            end

            # Finally for each property-value pair in element ordered by property perform the following steps:
            element.keys.sort.each do |property|
              value = element[property]

              # If no property member exists in the JSON object which is the value of the id member of activeGraph create the member and initialize its value to an empty array.
              activeGraph[id][property] ||= []

              # Recursively invoke this algorithm passing value as new element, id as new active subject, and property as new active property.
              generate_node_map(value,
                                nodeMap,
                                active_graph,
                                id,
                                property)
            end
          end
        end

        debug("nodeMap") {nodeMap.to_json(JSON_STATE)}
      end
    end

    private
    # Merge the last value into an array based for the specified key
    def merge_value(hash, key, value)
      (hash[key] ||= []) << value
    end

  end
end
