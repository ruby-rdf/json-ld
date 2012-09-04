module JSON::LD
  module Flatten
    include Utils

    ##
    # Build hash of nodes used for framing. Also returns flattened representation of input.
    #
    # @param [Array, Hash] element
    #   Expanded element
    # @param [Hash{String => Hash}] node_map
    #   map of nodes
    # @param [String] graph
    #   Graph name for results
    # @param [Array] list
    #   List for saving list elements
    # @param [BlankNodeNamer] namer
    def generate_node_map(element, node_map, graph, list, namer)
      depth do
        debug("nodeMap") {"element: #{element.inspect}, graph: #{graph}"}
        if element.is_a?(Array)
          element.map {|o| generate_node_map(o, node_map, graph, list, namer)}
        elsif !element.is_a?(Hash) || value?(element)
          list << element if list
        else
          # If the @id property exists and is an IRI, set id to its value, otherwise set it to a blank node identifier created by the Generate Blank Node Identifier algorithm.
          id = blank_node?(element) ? namer.get_name(element.fetch('@id', nil)) : element['@id']
          
          # If list is not null, append a new node reference to list using id at the value for @id.
          list << {'@id' => id} if list

          # Let nodes be the value in nodeMap where the key is graph; if no such value exists, insert a new JSON object for the key graph.
          debug("nodeMap") {"new graph: #{graph}"} unless node_map.has_key?(graph)
          nodes = (node_map[graph] ||= Hash.ordered)

          # If id is not in nodes, create a new JSON object node with id as the value for @id. Let node be the value of id in nodes.
          debug("nodeMap") {"new node: #{id}"} unless nodes.has_key?(id)
          node = (nodes[id] ||= Hash.ordered)
          node['@id'] ||= id

          # For each property that is not @id and each value in element ordered by property:
          element.each do |prop, value|
            case prop
            when '@id'
              # Skip @id, already assigned
            when '@graph'
              # If property is @graph, recursively call this algorithm passing value for element, nodeMap, null for list and if graph is @merged use graph, otherwise use id for graph and then continue.
              graph = graph == '@merged' ? '@merged' : id
              generate_node_map(value, node_map, graph, null, namer)
            when /^@(?!type)/
              # If property is not @type and is a keyword, merge property and value into node and then continue.
              node[prop] = value
            else
              raise InvalidFrame::Syntax,
                "unexpected value: #{value.inspect}, expected array" unless
                value.is_a?(Array)
              
              # For each value v in the array value:
              value.each do |v|
                if node?(v) || node_reference?(v)
                  # If v is a node definition or node reference:
                  # If the property @id is not an IRI or it does not exist, map v to a new blank node identifier to avoid collisions.
                  name = blank_node?(element) ?
                    namer.get_name(element.fetch('@id', nil)) :
                    element['@id']

                  # If one does not already exist, add a node reference for v into node for property.
                  node[prop] ||= []
                  node[prop] << {'@id' => name} unless node[prop].any? {|n|
                    node_ref?(n) && n['@id'] == name
                  }

                  # Recursively call this algorithm passing v for value, nodeMap, graph, and null for list.
                  generate_node_map(v, node_map, graph, null, namer)
                elsif list?(v)
                  # Otherwise if v has the property @list then recursively call this algorithm with the value of @list as element, nodeMap, graph, and a new array flattenedList as list.
                  flattened_list = []
                  generate_node_map(v['@list'],
                    node_map,
                    graph,
                    flattened_list,
                    namer)
                  # Create a new JSON object with the property @list set to flattenedList and add it to node for property.
                  node[prop] = {'@list' => flattened_list}
                elsif prop == '@type'
                  # Otherwise, if property is @type and v is not an IRI, generate a new blank node identifier and add it to node for property.
                  name = blank_node?({'@id' => v}) ? namer.get_name(v) : v
                  (node[prop] ||= []) << name
                else
                  # Otherwise, add v to node for property.
                  (node[prop] ||= []) << v
                end
              end
            end
          end
        end

        debug("nodeMap") {node_map.to_json(JSON_STATE)}
      end
    end
  end
end
