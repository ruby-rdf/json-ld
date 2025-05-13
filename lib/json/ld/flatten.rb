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
          subject_node = graph[active_subject]

          # Transform BNode types
          if element.key?('@type')
            element['@type'] = Array(element['@type']).map { |t| blank_node?(t) ? namer.get_name(t) : t }
          end

          if value?(element)
            element['@type'] = element['@type'].first if element['@type']

            # For rdfstar, if value contains an `@annotation` member ...
            # note: active_subject will not be nil.
            if annotation = element.delete('@annotation')
              # rdfstar being true is implicit, as it is checked in expansion
              as = if node_reference?(active_subject)
                active_subject['@id']
              else
                active_subject
              end

              reification = {'@id' => as, active_property => [element]}

              # Note that annotation is an array, make the reified subject the id of each member of that array.
              annotation.each do |a|
                # XXX may be zero or more reifiers; use bnode for now.
                reifier = namer.get_name
                a = a.merge('@id' => reifier, '@reifies' => reification)

                # Invoke recursively using annotation.
                create_node_map(a, graph_map, active_graph: active_graph, active_subject: reifier)
              end
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
          elsif triple_term?(element)
            # Add just the @triple member from element as the value of the property in the subject node.
            # FIXME: if a triple term can have other properties, the triple term would need to be its own entry in the node mode.
            add_value(subject_node, active_property, element.dup.delete_if {|k,v| k != '@triple'}, allow_duplicate: false)
            if element.keys.length != 1
              raise "Expected triple term to not have other properties, got #{element.inspect}"
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
              reference = { '@id' => id }
              if list.nil?
                add_value(subject_node, active_property, reference, property_is_array: true, allow_duplicate: false)
              else
                list['@list'] << reference
              end
            end

            # For rdfstar, if node contains an `@annotation` member ...
            # note: active_subject will not be nil
            # XXX: what if we're reversing an annotation?
            if annotation = element.delete('@annotation')
              # rdfstar being true is implicit, as it is checked in expansion
              as = if node_reference?(active_subject)
                active_subject['@id']
              else
                active_subject
              end

              reification = {'@id' => as, active_property => [{ '@id' => node['@id'] }]}

              # Note that annotation is an array, make the reified subject the id of each member of that array.
              annotation.each do |a|
                # XXX may be zero or more reifiers; use bnode for now.
                reifier = namer.get_name
                a = a.merge('@id' => reifier, '@reifies' => reification)

                # Invoke recursively using annotation.
                create_node_map(a, graph_map, active_graph: active_graph, active_subject: reifier)
              end
            end

            if element.key?('@reifies')
              add_value(node, '@reifies', element.delete('@reifies'), property_is_array: true, allow_duplicate: false)
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
      # Updates a node map from which annotations have been folded into reified triples to re-extract the annotations.
      #
      # Map entries having an `@reifies` key are used to find map entries that have a key based on the reification `@id` and a matching value. If found, the original map entry is removed and entries added to an `@annotation` property of the associated value.
      #
      # * If the map contains an entry with that value, and the associated antry has a item which matches the non-`@id` item from the map, the node is used to create an `@annotation` entry within that value.
      #
      # @param [Hash{String => Hash}] node_map
      # @return [Hash{String => Hash}]
      def create_annotations(node_map)
        node_map
          .select {|_, node| node.key?('@reifies')}
          .each do |key, node|

          reif_id = node['@id']
          reifs = node['@reifies']
          raise "expected the value of `@reifies` to be an array: #{reifs.inspect}" unless
            reifs.is_a?(Array)

          # The node has properties other than `@id` and `@reifies`
          annotation = node.dup.delete_if {|k, _| %w(@id @reifies).include?(k)}

          reifs.each do |reif|
            # node is a reification which _may_ relate to a value elsewhere in node_map
            raise "expected the value of `@reifies` to be an array: #{reifs.inspect}" unless
              reifs.is_a?(Array)
            target_id = reif['@id']
            target_node = node_map[target_id]
            next unless target_node

            # The reification should have just `@id` and an additional property
            reif_prop = (reif.keys - %w(@id)).first
            raise "expected reification to have a non-id key: #{node.keys.inspect}" unless
              reif_prop
            reif_values = reif[reif_prop]
            # There should be only a single value
            raise "expected a single reifiation property value: #{reif}" unless
              reif_values.length == 1

            reif_value = reif_values.first

            # If target_node has the matching property and a matching value
            target_values = target_node[reif_prop]
            next unless target_values

            # target_values must be an array
            raise "expected target propery value to have an array value: #{target_values.inspect}" unless
              target_values.is_a?(Array)

            target_values.each do |t_value|
              next unless t_value == reif_value

              # Add annotation to the identified value
              t_value['@annotation'] ||= []
              t_value['@annotation'] << {'@id' => reif_id}.merge(annotation)

              # This consumes the reification
              node['@reifies'] = node['@reifies'] - [reif]
            end
          end

          # If all reifications are consumed, remove the reification
          node_map.delete(reif_id) if node['@reifies'].empty?
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
