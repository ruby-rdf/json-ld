require 'rdf/nquads'

module JSON::LD
  module FromRDF
    include Utils

    ##
    # Generate a JSON-LD array representation from an array of `RDF::Statement`.
    # Representation is in expanded form
    #
    # @param [Array<RDF::Statement>, RDF::Enumerable] input
    # @return [Array<Hash>] the JSON-LD document in normalized form
    def from_statements(input)
      default_graph = {}
      graph_map = {'@default' => default_graph}

      value = nil
      ec = Context.new

      # Create a map for node to object representation

      # For each triple in input
      input.each do |statement|
        debug("statement") { statement.to_nquads.chomp}

        name = statement.context ? ec.expand_iri(statement.context).to_s : '@default'
        
        # Create a graph entry as needed
        node_map = graph_map[name] ||= {}
        default_graph[name] ||= {'@id' => name} unless name == '@default'
        
        subject = ec.expand_iri(statement.subject).to_s
        node = node_map[subject] ||= {'@id' => subject}

        # If object is an IRI or blank node identifier, does not equal rdf:nil, and node map does not have an object member, create one and initialize its value to a new JSON object consisting of a single member @id whose value is set to object.
        node_map[statement.object.to_s] ||= {'@id' => statement.object.to_s} unless
          statement.object.literal? || statement.object == RDF.nil

        # If predicate equals rdf:type, and object is an IRI or blank node identifier, append object to the value of the @type member of node. If no such member exists, create one and initialize it to an array whose only item is object. Finally, continue to the next RDF triple.
        if statement.predicate == RDF.type && statement.object.resource?
          merge_value(node, '@type', statement.object.to_s)
          next
        end

        # If object equals rdf:nil and predicate does not equal rdf:rest, set value to a new JSON object consisting of a single member @list whose value is set to an empty array.
        value = if statement.object == RDF.nil && statement.predicate != RDF.rest
          {'@list' => []}
        else
          ec.expand_value(nil, statement.object, @options)
        end

        merge_value(node, statement.predicate.to_s, value)

        # If object is a blank node identifier and predicate equals neither rdf:first nor rdf:rest, it might represent the head of a RDF list:
        if statement.object.node? && ![RDF.first, RDF.rest].include?(statement.predicate)
          merge_value(node_map[statement.object.to_s], :usages, value)
        end
      end

      # For each name and graph object in graph map:
      graph_map.each do |name, graph_object|
        subjects = graph_object.keys
        subjects.each do |subj|
          next unless graph_object.has_key?(subj)
          node = graph_object[subj]
          next unless node[:usages].is_a?(Array) && node[:usages].length == 1
          debug("list head") {node.to_json(JSON_STATE)}
          value = node[:usages].first
          list, list_nodes, subject = [], [], subj

          while subject != RDF.nil.to_s && list
            if node.nil? ||
               !blank_node?(node) ||
               node.keys.any? {|k| !["@id", :usages, RDF.first.to_s, RDF.rest.to_s].include?(k)} ||
               !(f = node[RDF.first.to_s]).is_a?(Array) || f.length != 1 ||
               !(r = node[RDF.rest.to_s]).is_a?(Array) || r.length != 1 || !node_reference?(r.first) ||
               list_nodes.include?(subject)

              debug("list") {"not valid list element: #{node.to_json(JSON_STATE)}"}
              debug {
                "bnode?: #{!blank_node?(node).inspect} " +
                "keys: #{node.keys.any? {|k| !["@id", :usages, RDF.first.to_s, RDF.rest.to_s].include?(k)}.inspect} " +
                "first: #{node[RDF.first.to_s].inspect} " +
                "rest: #{node[RDF.rest.to_s].inspect} " +
                "has sub: #{list_nodes.include?(subject).inspect}"
              }
              list = nil
            else
              list << f.first
              list_nodes << node['@id']
              subject = r.first['@id']
              node = graph_object[subject]
              debug("list") {"rest: #{node.to_json(JSON_STATE)}"}
              list = nil if list_nodes.include?(subject)
            end
          end

          next if list.nil?
          value.delete('@id')
          value['@list'] = list
          list_nodes.each {|s| graph_object.delete(s)}
        end
      end

      result = []
      debug("graph_map") {graph_map.to_json(JSON_STATE)}
      default_graph.keys.sort.each do |subject|
        node = default_graph[subject]
        if graph_map.has_key?(subject)
          node['@graph'] = []
          graph_map[subject].keys.sort.each do |s|
            n = graph_map[subject][s]
            n.delete(:usages)
            node['@graph'] << n unless node_reference?(n)
          end
        end
        node.delete(:usages)
        result << node unless node_reference?(node)
      end
      debug("fromRDF") {result.to_json(JSON_STATE)}
      result
    end
  end
end
