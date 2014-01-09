module JSON::LD
  module Flatten
    include Utils

    ##
    # This algorithm creates a JSON object node map holding an indexed representation of the graphs and nodes represented in the passed expanded document. All nodes that are not uniquely identified by an IRI get assigned a (new) blank node identifier. The resulting node map will have a member for every graph in the document whose value is another object with a member for every node represented in the document. The default graph is stored under the @default member, all other graphs are stored under their graph name.
    #
    # @param [Array, Hash] element
    #   Expanded element
    # @param [Hash{String => Hash}] node_map
    #   map of nodes
    # @param [String] active_graph
    #   The name of the currently active graph that the processor should use when processing.
    # @param [String] active_subject
    #   The currently active subject that the processor should use when processing.
    # @param [String] active_property
    #   The currently active property or keyword that the processor should use when processing.
    # @param [Array] list
    #   List for saving list elements
    def generate_node_map(element,
                          node_map,
                          active_graph    = '@default',
                          active_subject  = nil,
                          active_property = nil,
                          list            = nil)
      depth do
        debug("node_map") {"active_graph: #{active_graph}, element: #{element.inspect}"}
        debug("  =>") {"active_subject: #{active_subject.inspect}, active_property: #{active_property.inspect}, list: #{list.inspect}"}
        if element.is_a?(Array)
          # If element is an array, process each entry in element recursively by passing item for element, node map, active graph, active subject, active property, and list.
          element.map {|o|
            generate_node_map(o,
                              node_map,
                              active_graph,
                              active_subject,
                              active_property,
                              list)
          }
        else
          # Otherwise element is a JSON object. Reference the JSON object which is the value of the active graph member of node map using the variable graph. If the active subject is null, set node to null otherwise reference the active subject member of graph using the variable node.
          # Spec FIXME: initializing it to an empty JSON object, if necessary
          raise "Expected element to be a hash, was #{element.class}" unless element.is_a?(Hash)
          graph = node_map[active_graph] ||= {}
          node = graph[active_subject] if active_subject

          # If element has an @type member, perform for each item the following steps:
          if element.has_key?('@type')
            types = Array(element['@type']).map do |item|
              # If item is a blank node identifier, replace it with a newly generated blank node identifier passing item for identifier.
              blank_node?(item) ? namer.get_name(item) : item
            end

            element['@type'] = element['@type'].is_a?(Array) ? types : types.first
          end

          # If element has an @value member, perform the following steps:
          if value?(element)
            unless list
              # If no list has been passed, merge element into the active property member of the active subject in graph.
              merge_value(node, active_property, element)
            else
              # Otherwise, append element to the @list member of list.
              merge_value(list, '@list', element)
            end
          elsif list?(element)
            # Otherwise, if element has an @list member, perform the following steps:
            # Initialize a new JSON object result having a single member @list whose value is initialized to an empty array.
            result = {'@list' => []}

            # Recursively call this algorithm passing the value of element's @list member as new element and result as list.
            generate_node_map(element['@list'],
                              node_map,
                              active_graph,
                              active_subject,
                              active_property,
                              result)

            # Append result to the the value of the active property member of node.
            debug("node_map") {"@list: #{result.inspect}"}
            merge_value(node, active_property, result)
          else
            # Otherwise element is a node object, perform the following steps:

            # If element has an @id member, set id to its value and remove the member from element. If id is a blank node identifier, replace it with a newly generated blank node identifier passing id for identifier.
            # Otherwise, set id to the result of the Generate Blank Node Identifier algorithm passing null for identifier.
            id = element.delete('@id')
            id = namer.get_name(id) if blank_node?(id)
            debug("node_map") {"id: #{id.inspect}"}

            # If graph does not contain a member id, create one and initialize it to a JSON object consisting of a single member @id whose value is set to id.
            graph[id] ||= {'@id' => id}

            # If active property is not null, perform the following steps:
            if node?(active_subject) || node_reference?(active_subject)
              debug("node_map") {"active_subject is an object, merge into #{id}"}
              merge_value(graph[id], active_property, active_subject)
            elsif active_property
              # Create a new JSON object reference consisting of a single member @id whose value is id.
              reference = {'@id' => id}

              # If list is null:
              unless list
                merge_value(node, active_property, reference)
              else
                merge_value(list, '@list', reference)
              end
            end

            # Reference the value of the id member of graph using the variable node.
            node = graph[id]

            # If element has an @type key, append each item of its associated array to the array associated with the @type key of node unless it is already in that array. Finally remove the @type member from element.
            if element.has_key?('@type')
              Array(element.delete('@type')).each do |t|
                merge_value(node, '@type', t)
              end
            end

            # If element has an @index member, set the @index member of node to its value. If node has already an @index member with a different value, a conflicting indexes error has been detected and processing is aborted. Otherwise, continue by removing the @index member from element.
            if element.has_key?('@index')
              raise JsonLdError::ConflictingIndexes,
                    "Element already has index #{node['@index']} dfferent from #{element['@index']}" if
                    node['@index'] && node['@index'] != element['@index']
              node['@index'] = element.delete('@index')
            end

            # If element has an @reverse member:
            if element.has_key?('@reverse')
              element.delete('@reverse').each do |property, values|
                values.each do |value|
                  debug("node_map") {"@reverse(#{id}): #{value.inspect}"}
                  # Recursively invoke this algorithm passing value for element, node map, and active graph.
                  generate_node_map(value,
                                    node_map,
                                    active_graph,
                                    {'@id' => id},
                                    property)
                end
              end
            end

            # If element has an @graph member, recursively invoke this algorithm passing the value of the @graph member for element, node map, and id for active graph before removing the @graph member from element.
            if element.has_key?('@graph')
              generate_node_map(element.delete('@graph'),
                                node_map,
                                id)
            end

            # Finally, for each key-value pair property-value in element ordered by property perform the following steps:
            # Note: Not ordering doesn't seem to affect results and is more performant
            element.keys.each do |property|
              value = element[property]

              # If property is a blank node identifier, replace it with a newly generated blank node identifier passing property for identifier.
              property = namer.get_name(property) if blank_node?(property)

              # If node does not have a property member, create one and initialize its value to an empty array.
              node[property] ||= []

              # Recursively invoke this algorithm passing value as new element, id as new active subject, and property as new active property.
              generate_node_map(value,
                                node_map,
                                active_graph,
                                id,
                                property)
            end
          end
        end

        debug("node_map") {node_map.to_json(JSON_STATE)}
      end
    end
  end
end
