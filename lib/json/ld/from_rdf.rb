# frozen_string_literal: true

require 'rdf/nquads'

module JSON
  module LD
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
      # @param extendedRepresentation (false)
      #   Use the extended internal representation for native types.
      #
      # @return [Array<Hash>] the JSON-LD document in normalized form
      def from_statements(dataset, useRdfType: false, useNativeTypes: false, extendedRepresentation: false)
        default_graph = {}
        graph_map = { '@default' => default_graph }
        referenced_once = {}

        value = nil

        # Create an entry for compound-literal node detection
        compound_literal_subjects = {}

        # Create a map for node to object representation

        # For each statement in dataset
        dataset.each do |statement|
          # log_debug("statement") { statement.to_nquads.chomp}

          name = if statement.graph_name
            @context.expand_iri(statement.graph_name,
              base: @options[:base]).to_s
          else
            '@default'
          end

          # Create a graph entry as needed
          node_map = graph_map[name] ||= {}
          compound_literal_subjects[name] ||= {}

          default_graph[name] ||= { '@id' => name } unless name == '@default'

          subject = if statement.subject.statement?
            resource_representation(statement.subject, useNativeTypes, extendedRepresentation)['@id'].to_json_c14n
          else
            statement.subject.to_s
          end
          node = node_map[subject] ||= resource_representation(statement.subject, useNativeTypes,
            extendedRepresentation)

          # If predicate is rdf:datatype, note subject in compound literal subjects map
          if @options[:rdfDirection] == 'compound-literal' && statement.predicate == RDF_DIRECTION
            compound_literal_subjects[name][subject] ||= true
          end

          # If object is an IRI, blank node identifier, or statement, and node map does not have an object member, create one and initialize its value to a new JSON object consisting of a single member @id whose value is set to object.
          unless statement.object.literal?
            object = if statement.object.statement?
              resource_representation(statement.object, useNativeTypes, extendedRepresentation)['@id'].to_json_c14n
            else
              statement.object.to_s
            end
            node_map[object] ||=
              resource_representation(statement.object, useNativeTypes, extendedRepresentation)
          end

          # If predicate equals rdf:type, and object is an IRI or blank node identifier, append object to the value of the @type member of node. If no such member exists, create one and initialize it to an array whose only item is object. Finally, continue to the next RDF triple.
          if statement.predicate == RDF.type && statement.object.resource? && !useRdfType
            merge_value(node, '@type', statement.object.to_s)
            next
          end

          # Set value to the result of using the RDF to Object Conversion algorithm, passing object, rdfDirection, and use native types.
          value = resource_representation(statement.object, useNativeTypes, extendedRepresentation)

          merge_value(node, statement.predicate.to_s, value)

          # If object is a blank node identifier or rdf:nil, it might represent the a list node:
          if statement.object == RDF.nil
            # Append a new JSON object consisting of three members, node, property, and value to the usages array. The node member is set to a reference to node, property to predicate, and value to a reference to value.
            object = node_map[statement.object.to_s]
            merge_value(object, :usages, {
              node: node,
              property: statement.predicate.to_s,
              value: value
            })
          elsif referenced_once.key?(statement.object.to_s)
            referenced_once[statement.object.to_s] = false
          elsif statement.object.node?
            referenced_once[statement.object.to_s] = {
              node: node,
              property: statement.predicate.to_s,
              value: value
            }
          end
        end

        # For each name and graph object in graph map:
        graph_map.each do |name, graph_object|
          # If rdfDirection is compound-literal, check referenced_once for entries from compound_literal_subjects
          compound_literal_subjects.fetch(name, {}).each_key do |cl|
            node = referenced_once[cl][:node]
            next unless node.is_a?(Hash)

            property = referenced_once[cl][:property]
            value = referenced_once[cl][:value]
            cl_node = graph_map[name].delete(cl)
            next unless cl_node.is_a?(Hash)

            node[property].select do |v|
              next unless v['@id'] == cl

              v.delete('@id')
              v['@value'] = cl_node[RDF.value.to_s].first['@value']
              if (langs = cl_node[RDF_LANGUAGE.to_s])
                lang = langs.first['@value']
                unless /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(lang)
                  warn "i18n datatype language must be valid BCP47: #{lang.inspect}"
                end
                v['@language'] = lang
              end
              v['@direction'] = cl_node[RDF_DIRECTION.to_s].first['@value']
            end
          end

          nil_var = graph_object.fetch(RDF.nil.to_s, {})

          # For each item usage in the usages member of nil, perform the following steps:
          nil_var.fetch(:usages, []).each do |usage|
            node = usage[:node]
            property = usage[:property]
            head = usage[:value]
            list = []
            list_nodes = []

            # If property equals rdf:rest, the value associated to the usages member of node has exactly 1 entry, node has a rdf:first and rdf:rest property, both of which have as value an array consisting of a single element, and node has no other members apart from an optional @type member whose value is an array with a single item equal to rdf:List, node represents a well-formed list node. Continue with the following steps:
            # log_debug("list element?") {node.to_json(JSON_STATE) rescue 'malformed json'}
            while property == RDF.rest.to_s &&
                  blank_node?(node) &&
                  referenced_once[node['@id']] &&
                  node.keys.none? { |k| !["@id", '@type', :usages, RDF.first.to_s, RDF.rest.to_s].include?(k) } &&
                  (f = node[RDF.first.to_s]).is_a?(Array) && f.length == 1 &&
                  (r = node[RDF.rest.to_s]).is_a?(Array) && r.length == 1 &&
                  ((t = node['@type']).nil? || t == [RDF.List.to_s])
              list << Array(node[RDF.first.to_s]).first
              list_nodes << node['@id']

              # get next node, moving backwards through list
              node_usage = referenced_once[node['@id']]
              node = node_usage[:node]
              property = node_usage[:property]
              head = node_usage[:value]
            end

            head.delete('@id')
            head['@list'] = list.reverse
            list_nodes.each { |node_id| graph_object.delete(node_id) }
          end

          # Create annotations on graph object
          create_annotations(graph_object)
        end

        result = []
        default_graph.keys.opt_sort(ordered: @options[:ordered]).each do |subject|
          node = default_graph[subject]
          if graph_map.key?(subject)
            node['@graph'] = []
            graph_map[subject].keys.opt_sort(ordered: @options[:ordered]).each do |s|
              n = graph_map[subject][s]
              n.delete(:usages)
              node['@graph'] << n unless node_reference?(n)
            end
          end
          node.delete(:usages)
          result << node unless node_reference?(node)
        end
        # log_debug("fromRdf") {result.to_json(JSON_STATE) rescue 'malformed json'}
        result
      end

      private

      RDF_LITERAL_NATIVE_TYPES = Set.new([RDF::XSD.boolean, RDF::XSD.integer, RDF::XSD.double]).freeze

      def resource_representation(resource, useNativeTypes, extendedRepresentation)
        case resource
        when RDF::Statement
          # Note, if either subject or object are a BNode which is used elsewhere,
          # this might not work will with the BNode accounting from above.
          rep = { '@id' => resource_representation(resource.subject, false, extendedRepresentation) }
          if resource.predicate == RDF.type
            rep['@id']['@type'] = resource.object.to_s
          else
            rep['@id'][resource.predicate.to_s] =
              as_array(resource_representation(resource.object, useNativeTypes, extendedRepresentation))
          end
          rep
        when RDF::Literal
          base = @options[:base]
          rdfDirection = @options[:rdfDirection]
          res = {}

          if resource.datatype == RDF_JSON && @context.processingMode('json-ld-1.1')
            res['@type'] = '@json'
            res['@value'] = begin
              ::JSON.parse(resource.object)
            rescue ::JSON::ParserError => e
              raise JSON::LD::JsonLdError::InvalidJsonLiteral, e.message
            end
          elsif useNativeTypes && extendedRepresentation
            res['@value'] = resource  # Raw literal
          elsif resource.datatype.start_with?("https://www.w3.org/ns/i18n#") && rdfDirection == 'i18n-datatype' && @context.processingMode('json-ld-1.1')
            lang, dir = resource.datatype.fragment.split('_')
            res['@value'] = resource.to_s
            unless lang.empty?
              unless /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(lang)
                if options[:validate]
                  raise JsonLdError::InvalidLanguageMapping, "rdf:language must be valid BCP47: #{lang.inspect}"
                end

                warn "rdf:language must be valid BCP47: #{lang.inspect}"

              end
              res['@language'] = lang
            end
            res['@direction'] = dir
          elsif useNativeTypes && RDF_LITERAL_NATIVE_TYPES.include?(resource.datatype) && resource.valid?
            res['@value'] = resource.object
          else
            resource.canonicalize! if resource.valid? && resource.datatype == RDF::XSD.double
            if resource.datatype?
              res['@type'] = resource.datatype.to_s
            elsif resource.language?
              res['@language'] = resource.language.to_s
            end
            res['@value'] = resource.to_s
          end
          res
        else
          { '@id' => resource.to_s }
        end
      end
    end
  end
end
