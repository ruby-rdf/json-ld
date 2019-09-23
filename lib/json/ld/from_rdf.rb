# -*- encoding: utf-8 -*-
# frozen_string_literal: true
require 'rdf/nquads'

module JSON::LD
  module FromRDF
    include Utils

    ##
    # Generate a JSON-LD array representation from an array of `RDF::Statement`.
    # Representation is in expanded form
    #
    # @param [Array<RDF::Statement>, RDF::Enumerable] dataset
    # @param [Boolean] useRdfType (false)
    #   If set to `true`, the JSON-LD processor will treat `rdf:type` like a normal property instead of using `@type`.
    # @param [Boolean] useNativeTypes (false) use native representations
    # @param [Boolean] ordered (true)
    #   Ensure output objects have keys ordered properly
    # @return [Array<Hash>] the JSON-LD document in normalized form
    def from_statements(dataset, useRdfType: false, useNativeTypes: false, ordered: false)
      default_graph = {}
      graph_map = {'@default' => default_graph}
      referenced_once = {}

      value = nil
      ec = @context

      # Create a map for node to object representation

      # For each statement in dataset
      dataset.each do |statement|
        #log_debug("statement") { statement.to_nquads.chomp}

        name = statement.graph_name ? ec.expand_iri(statement.graph_name).to_s : '@default'

        # Create a graph entry as needed
        node_map = graph_map[name] ||= {}
        default_graph[name] ||= {'@id' => name} unless name == '@default'

        subject = ec.expand_iri(statement.subject).to_s
        node = node_map[subject] ||= {'@id' => subject}

        # If object is an IRI or blank node identifier, and node map does not have an object member, create one and initialize its value to a new JSON object consisting of a single member @id whose value is set to object.
        node_map[statement.object.to_s] ||= {'@id' => statement.object.to_s} unless
          statement.object.literal?

        # If predicate equals rdf:type, and object is an IRI or blank node identifier, append object to the value of the @type member of node. If no such member exists, create one and initialize it to an array whose only item is object. Finally, continue to the next RDF triple.
        if statement.predicate == RDF.type && statement.object.resource? && !useRdfType
          merge_value(node, '@type', statement.object.to_s)
          next
        end

        # Set value to the result of using the RDF to Object Conversion algorithm, passing object and use native types.
        value = ec.expand_value(nil, statement.object, useNativeTypes: useNativeTypes, log_depth: @options[:log_depth])

        merge_value(node, statement.predicate.to_s, value)

        # If object is a blank node identifier or rdf:nil, it might represent the a list node:
        if statement.object == RDF.nil
          # Append a new JSON object consisting of three members, node, property, and value to the usages array. The node member is set to a reference to node, property to predicate, and value to a reference to value.
          object = node_map[statement.object.to_s]
          merge_value(object, :usages, {
            node:     node,
            property: statement.predicate.to_s,
            value:    value
          })
        elsif referenced_once.has_key?(statement.object.to_s)
          referenced_once[statement.object.to_s] = false
        elsif statement.object.node?
          referenced_once[statement.object.to_s] = {
            node:     node,
            property: statement.predicate.to_s,
            value:    value
          }
        end
      end

      # For each name and graph object in graph map:
      graph_map.each do |name, graph_object|
        next unless nil_var = graph_object[RDF.nil.to_s]

        # For each item usage in the usages member of nil, perform the following steps:
        nil_var.fetch(:usages, []).each do |usage|
          node, property, head = usage[:node], usage[:property], usage[:value]
          list, list_nodes = [], []

          # If property equals rdf:rest, the value associated to the usages member of node has exactly 1 entry, node has a rdf:first and rdf:rest property, both of which have as value an array consisting of a single element, and node has no other members apart from an optional @type member whose value is an array with a single item equal to rdf:List, node represents a well-formed list node. Continue with the following steps:
          #log_debug("list element?") {node.to_json(JSON_STATE) rescue 'malformed json'}
          while property == RDF.rest.to_s &&
              blank_node?(node) &&
              referenced_once[node['@id']] &&
              node.keys.none? {|k| !["@id", '@type', :usages, RDF.first.to_s, RDF.rest.to_s].include?(k)} &&
              (f = node[RDF.first.to_s]).is_a?(Array) && f.length == 1 &&
              (r = node[RDF.rest.to_s]).is_a?(Array) && r.length == 1 &&
              ((t = node['@type']).nil? || t == [RDF.List.to_s])
            list << Array(node[RDF.first.to_s]).first
            list_nodes << node['@id']

            # get next node, moving backwards through list
            node_usage = referenced_once[node['@id']]
            node, property, head = node_usage[:node], node_usage[:property], node_usage[:value]
          end

          head.delete('@id')
          head['@list'] = list.reverse
          list_nodes.each {|node_id| graph_object.delete(node_id)}
        end
      end

      result = []
      default_graph.keys.opt_sort(ordered: ordered).each do |subject|
        node = default_graph[subject]
        if graph_map.has_key?(subject)
          node['@graph'] = []
          graph_map[subject].keys.opt_sort(ordered: ordered).each do |s|
            n = graph_map[subject][s]
            n.delete(:usages)
            node['@graph'] << n unless node_reference?(n)
          end
        end
        node.delete(:usages)
        result << node unless node_reference?(node)
      end
      #log_debug("fromRdf") {result.to_json(JSON_STATE) rescue 'malformed json'}
      result
    end
  end
end
