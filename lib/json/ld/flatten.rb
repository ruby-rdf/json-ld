# -*- encoding: utf-8 -*-
# frozen_string_literal: true
module JSON::LD
  module Flatten
    include Utils

    ##
    # This algorithm creates a JSON object node map holding an indexed representation of the graphs and nodes represented in the passed expanded document. All nodes that are not uniquely identified by an IRI get assigned a (new) blank node identifier. The resulting node map will have a member for every graph in the document whose value is another object with a member for every node represented in the document. The default graph is stored under the @default member, all other graphs are stored under their graph name.
    #
    # @param [Array, Hash] element
    #   Expanded JSON-LD input
    # @param [Hash] graph_map A map of graph name to subjects
    # @param [String] active_graph
    #   The name of the currently active graph that the processor should use when processing.
    # @param [String] active_subject (nil)
    #   Node identifier
    # @param [String] active_property (nil)
    #   Property within current node
    # @param [Array] list (nil)
    #   Used when property value is a list
    # @param [Boolean] ordered (true)
    #   Ensure output objects have keys ordered properly
    def create_node_map(element, graph_map,
                        active_graph: '@default',
                        active_subject: nil,
                        active_property: nil,
                        list: nil)
      log_debug("node_map") {"active_graph: #{active_graph}, element: #{element.inspect}, active_subject: #{active_subject}"}
      if element.is_a?(Array)
        # If element is an array, process each entry in element recursively by passing item for element, node map, active graph, active subject, active property, and list.
        element.map do |o|
          create_node_map(o, graph_map,
                          active_graph: active_graph,
                          active_subject: active_subject,
                          active_property: active_property,
                          list: list)
        end
      elsif !element.is_a?(Hash)
        raise "Expected hash or array to create_node_map, got #{element.inspect}"
      else
        graph = (graph_map[active_graph] ||= {})
        subject_node = graph[active_subject]

        # Transform BNode types
        if element.has_key?('@type')
          element['@type'] = Array(element['@type']).map {|t| blank_node?(t) ? namer.get_name(t) : t}
        end

        if value?(element)
          element['@type'] = element['@type'].first if element ['@type']
          if list.nil?
            add_value(subject_node, active_property, element, property_is_array: true, allow_duplicate: false)
          else
            list['@list'] << element
          end
        elsif list?(element)
          result = {'@list' => []}
          create_node_map(element['@list'], graph_map,
                          active_graph: active_graph,
                          active_subject: active_subject,
                          active_property: active_property,
                          list: result)
          if list.nil?
            add_value(subject_node, active_property, result, property_is_array: true)
          else
            list['@list'] << result
          end
        else
          # Element is a node object
          id = element.delete('@id')
          id = namer.get_name(id) if blank_node?(id)

          node = graph[id] ||= {'@id' => id}

          if active_subject.is_a?(Hash)
            # If subject is a hash, then we're processing a reverse-property relationship.
            add_value(node, active_property, active_subject, property_is_array: true, allow_duplicate: false)
          elsif active_property
            reference = {'@id' => id}
            if list.nil?
              add_value(subject_node, active_property, reference, property_is_array: true, allow_duplicate: false)
            else
              list['@list'] << reference
            end
          end

          if element.has_key?('@type')
            add_value(node, '@type', element.delete('@type'), property_is_array: true, allow_duplicate: false)
          end

          if element['@index']
            raise JsonLdError::ConflictingIndexes,
                  "Element already has index #{node['@index']} dfferent from #{element['@index']}" if
                  node.key?('@index') && node['@index'] != element['@index']
            node['@index'] = element.delete('@index')
          end

          if element['@reverse']
            referenced_node, reverse_map = {'@id' => id}, element.delete('@reverse')
            reverse_map.each do |property, values|
              values.each do |value|
                create_node_map(value, graph_map,
                                active_graph: active_graph,
                                active_subject: referenced_node,
                                active_property: property)
              end
            end
          end

          if element['@graph']
            create_node_map(element.delete('@graph'), graph_map,
                            active_graph: id)
          end

          element.keys.each do |property|
            value = element[property]

            property = namer.get_name(property) if blank_node?(property)
            node[property] ||= []
            create_node_map(value, graph_map,
                            active_graph: active_graph,
                            active_subject: id,
                            active_property: property)
          end
        end
      end
    end

  private
    ##
    # Merge nodes from all graphs in the graph_map into a new node map
    #
    # @param [Hash{String => Hash}] graph_map
    # @return [Hash]
    def merge_node_map_graphs(graph_map)
      merged = {}
      graph_map.each do |name, node_map|
        node_map.each do |id, node|
          merged_node = (merged[id] ||= {'@id' => id})

          # Iterate over node properties
          node.each do |property, values|
            if property.start_with?('@')
              # Copy keywords
              merged_node[property] = node[property].dup
            else
              # Merge objects
              values.each do |value|
                add_value(merged_node, property, value.dup, property_is_array: true)
              end
            end
          end
        end
      end

      merged
    end
  end
end
