# frozen_string_literal: true

require 'json/canonicalization'

module JSON
  module LD
    module Flatten
      include Utils

      ##
      # This algorithm creates a JSON object node map holding an indexed representation of the graphs and nodes represented in the passed expanded document. All nodes that are not uniquely identified by an IRI get assigned a (new) blank node identifier. The resulting node map will have a member for every graph in the document whose value is another object with a member for every node represented in the document. The default graph is stored under the @default member, all other graphs are stored under their graph name.
      #
      # For RDF-star/JSON-LD-star:
      #   * Values of `@id` can be an object (embedded node); when these are used as keys in a Node Map, they are serialized as canonical JSON, and de-serialized when flattening.
      #   * The presence of `@annotation` implies an embedded node and the annotation object is removed from the node/value object in which it appears.
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
      # @param [Boolean] reverse (false)
      #   Processing a reverse relationship
      # @param [Array] list (nil)
      #   Used when property value is a list
      def create_node_map(element, graph_map,
                          active_graph: '@default',
                          active_subject: nil,
                          active_property: nil,
                          reverse: false,
                          list: nil)
        if element.is_a?(Array)
          # If element is an array, process each entry in element recursively by passing item for element, node map, active graph, active subject, active property, and list.
          element.map do |o|
            create_node_map(o, graph_map,
              active_graph: active_graph,
              active_subject: active_subject,
              active_property: active_property,
              reverse: false,
              list: list)
          end
        elsif !element.is_a?(Hash)
          raise "Expected hash or array to create_node_map, got #{element.inspect}"
        else
          graph = (graph_map[active_graph] ||= {})
          subject_node = !reverse && graph[active_subject.is_a?(Hash) ? active_subject.to_json_c14n : active_subject]

          # Transform BNode types
          if element.key?('@type')
            element['@type'] = Array(element['@type']).map { |t| blank_node?(t) ? namer.get_name(t) : t }
          end

          if value?(element)
            element['@type'] = element['@type'].first if element['@type']

            # For rdfstar, if value contains an `@annotation` member ...
            # note: active_subject will not be nil, and may be an object itself.
            if element.key?('@annotation')
              # rdfstar being true is implicit, as it is checked in expansion
              as = if node_reference?(active_subject)
                active_subject['@id']
              else
                active_subject
              end
              star_subject = {
                "@id" => as,
                active_property => [element]
              }

              # Note that annotation is an array, make the reified subject the id of each member of that array.
              annotation = element.delete('@annotation').map do |a|
                a.merge('@id' => star_subject)
              end

              # Invoke recursively using annotation.
              create_node_map(annotation, graph_map,
                active_graph: active_graph)
            end

            if list.nil?
              add_value(subject_node, active_property, element, property_is_array: true, allow_duplicate: false)
            else
              list['@list'] << element
            end
          elsif list?(element)
            result = { '@list' => [] }
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
            ser_id = id = element.delete('@id')
            if id.is_a?(Hash)
              # Index graph using serialized id
              ser_id = id.to_json_c14n
            elsif id.nil?
              ser_id = id = namer.get_name
            end

            node = graph[ser_id] ||= { '@id' => id }

            if reverse
              # NOTE: active_subject is a Hash
              # We're processing a reverse-property relationship.
              add_value(node, active_property, active_subject, property_is_array: true, allow_duplicate: false)
            elsif active_property
              reference = { '@id' => id }
              if list.nil?
                add_value(subject_node, active_property, reference, property_is_array: true, allow_duplicate: false)
              else
                list['@list'] << reference
              end
            end

            # For rdfstar, if node contains an `@annotation` member ...
            # note: active_subject will not be nil, and may be an object itself.
            # XXX: what if we're reversing an annotation?
            if element.key?('@annotation')
              # rdfstar being true is implicit, as it is checked in expansion
              as = if node_reference?(active_subject)
                active_subject['@id']
              else
                active_subject
              end
              star_subject = if reverse
                { "@id" => node['@id'], active_property => [{ '@id' => as }] }
              else
                { "@id" => as, active_property => [{ '@id' => node['@id'] }] }
              end

              # Note that annotation is an array, make the reified subject the id of each member of that array.
              annotation = element.delete('@annotation').map do |a|
                a.merge('@id' => star_subject)
              end

              # Invoke recursively using annotation.
              create_node_map(annotation, graph_map,
                active_graph: active_graph,
                active_subject: star_subject)
            end

            if element.key?('@type')
              add_value(node, '@type', element.delete('@type'), property_is_array: true, allow_duplicate: false)
            end

            if element['@index']
              if node.key?('@index') && node['@index'] != element['@index']
                raise JsonLdError::ConflictingIndexes,
                  "Element already has index #{node['@index']} dfferent from #{element['@index']}"
              end
              node['@index'] = element.delete('@index')
            end

            if element['@reverse']
              referenced_node = { '@id' => id }
              reverse_map = element.delete('@reverse')
              reverse_map.each do |property, values|
                values.each do |value|
                  create_node_map(value, graph_map,
                    active_graph: active_graph,
                    active_subject: referenced_node,
                    active_property: property,
                    reverse: true)
                end
              end
            end

            if element['@graph']
              create_node_map(element.delete('@graph'), graph_map,
                active_graph: id)
            end

            if element['@included']
              create_node_map(element.delete('@included'), graph_map,
                active_graph: active_graph)
            end

            element.each_key do |property|
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

      ##
      # Create annotations
      #
      # Updates a node map from which annotations have been folded into embedded triples to re-extract the annotations.
      #
      # Map entries where the key is of the form of a canonicalized JSON object are used to find keys with the `@id` and property components. If found, the original map entry is removed and entries added to an `@annotation` property of the associated value.
      #
      # * Keys which are of the form of a canonicalized JSON object are examined in inverse order of length.
      # * Deserialize the key into a map, and re-serialize the value of `@id`.
      # * If the map contains an entry with that value (after re-canonicalizing, as appropriate), and the associated antry has a item which matches the non-`@id` item from the map, the node is used to create an `@annotation` entry within that value.
      #
      # @param [Hash{String => Hash}] node_map
      # @return [Hash{String => Hash}]
      def create_annotations(node_map)
        node_map.keys
          .select { |k| k.start_with?('{') }
          .sort_by(&:length)
          .reverse_each do |key|
          annotation = node_map[key]
          # Deserialize key, and re-serialize the `@id` value.
          emb = annotation['@id'].dup
          id = emb.delete('@id')
          property, value = emb.to_a.first

          # If id is a map, set it to the result of canonicalizing that value, otherwise to itself.
          id = id.to_json_c14n if id.is_a?(Hash)

          next unless node_map.key?(id)

          # If node map has an entry for id and that entry contains the same property and value from entry:
          node = node_map[id]

          next unless node.key?(property)

          node[property].each do |emb_value|
            next unless emb_value == value.first

            node_map.delete(key)
            annotation.delete('@id')
            add_value(emb_value, '@annotation', annotation, property_is_array: true) unless
              annotation.empty?
          end
        end
      end

      ##
      # Rename blank nodes recursively within an embedded object
      #
      # @param [Object] node
      # @return [Hash]
      def rename_bnodes(node)
        case node
        when Array
          node.map { |n| rename_bnodes(n) }
        when Hash
          node.each_with_object({}) do |(k, v), memo|
            v = namer.get_name(v) if k == '@id' && v.is_a?(String) && blank_node?(v)
            memo[k] = rename_bnodes(v)
          end
        else
          node
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
        graph_map.each do |_name, node_map|
          node_map.each do |id, node|
            merged_node = (merged[id] ||= { '@id' => id })

            # Iterate over node properties
            node.each do |property, values|
              if property != '@type' && property.start_with?('@')
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
end
