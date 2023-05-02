# frozen_string_literal: true

require 'rdf'
require 'rdf/nquads'
require 'json/canonicalization'

module JSON
  module LD
    module ToRDF
      include Utils

      ##
      # @param [Hash{String => Object}] item
      # @param [RDF::Resource] graph_name
      # @param [Boolean] quoted emitted triples are quoted triples.
      # @yield statement
      # @yieldparam [RDF::Statement] statement
      # @return RDF::Resource the subject of this item
      def item_to_rdf(item, graph_name: nil, quoted: false, &block)
        # Just return value object as Term
        return unless item

        if value?(item)
          value = item.fetch('@value')
          datatype = item.fetch('@type', nil)

          datatype = RDF_JSON if datatype == '@json'

          case value
          when RDF::Value
            return value
          when TrueClass, FalseClass
            # If value is true or false, then set value its canonical lexical form as defined in the section Data Round Tripping. If datatype is null, set it to xsd:boolean.
            value = value.to_s
            datatype ||= RDF::XSD.boolean.to_s
          when Numeric
            # Otherwise, if value is a number, then set value to its canonical lexical form as defined in the section Data Round Tripping. If datatype is null, set it to either xsd:integer or xsd:double, depending on if the value contains a fractional and/or an exponential component.
            value = if datatype == RDF_JSON
              value.to_json_c14n
            else
              # Don't serialize as double if there are no fractional bits
              as_double = value.ceil != value || value >= 1e21 || datatype == RDF::XSD.double
              lit = if as_double
                RDF::Literal::Double.new(value, canonicalize: true)
              else
                RDF::Literal.new(value.numerator, canonicalize: true)
              end

              datatype ||= lit.datatype
              lit.to_s.sub("E+", "E")
            end
          when Array, Hash
            # Only valid for rdf:JSON
            value = value.to_json_c14n
          else
            if item.key?('@direction') && @options[:rdfDirection]
              # Either serialize using a datatype, or a compound-literal
              case @options[:rdfDirection]
              when 'i18n-datatype'
                datatype = RDF::URI("https://www.w3.org/ns/i18n##{item.fetch('@language',
                  '').downcase}_#{item['@direction']}")
              when 'compound-literal'
                cl = RDF::Node.new
                yield RDF::Statement(cl, RDF.value, item['@value'].to_s)
                yield RDF::Statement(cl, RDF_LANGUAGE, item['@language'].downcase) if item['@language']
                yield RDF::Statement(cl, RDF_DIRECTION, item['@direction'])
                return cl
              end
            end

            # Otherwise, if datatype is null, set it to xsd:string or xsd:langString, depending on if item has a @language key.
            datatype ||= item.key?('@language') ? RDF.langString : RDF::XSD.string
            value = value.to_json_c14n if datatype == RDF_JSON
          end
          datatype = RDF::URI(datatype) if datatype && !datatype.is_a?(RDF::URI)

          # Initialize literal as an RDF literal using value and datatype. If element has the key @language and datatype is xsd:string, then add the value associated with the @language key as the language of the object.
          language = item.fetch('@language', nil) if datatype == RDF.langString
          return RDF::Literal.new(value, datatype: datatype, language: language)
        elsif list?(item)
          # If item is a list object, initialize list_results as an empty array, and object to the result of the List Conversion algorithm, passing the value associated with the @list key from item and list_results.
          return parse_list(item['@list'], graph_name: graph_name, &block)
        end

        subject = case item['@id']
        when nil then node
        when String then as_resource(item['@id'])
        when Object
          # Embedded/quoted statement
          # (No error checking, as this is done in expansion)
          to_enum(:item_to_rdf, item['@id'], quoted: true).to_a.first
        end

        # log_debug("item_to_rdf")  {"subject: #{subject.to_ntriples rescue 'malformed rdf'}"}
        item.each do |property, values|
          case property
          when '@type'
            # If property is @type, construct triple as an RDF Triple composed of id, rdf:type, and object from values where id and object are represented either as IRIs or Blank Nodes
            values.each do |v|
              object = as_resource(v)
              # log_debug("item_to_rdf")  {"type: #{object.to_ntriples rescue 'malformed rdf'}"}
              yield RDF::Statement(subject, RDF.type, object, graph_name: graph_name, quoted: quoted)
            end
          when '@graph'
            values = [values].compact unless values.is_a?(Array)
            values.each do |nd|
              item_to_rdf(nd, graph_name: subject, quoted: quoted, &block)
            end
          when '@reverse'
            raise "Huh?" unless values.is_a?(Hash)

            values.each do |prop, vv|
              predicate = as_resource(prop)
              # log_debug("item_to_rdf")  {"@reverse predicate: #{predicate.to_ntriples rescue 'malformed rdf'}"}
              # For each item in values
              vv.each do |v|
                # Item is a node definition. Generate object as the result of the Object Converstion algorithm passing item.
                object = item_to_rdf(v, graph_name: graph_name, &block)
                # log_debug("item_to_rdf")  {"subject: #{object.to_ntriples rescue 'malformed rdf'}"}
                # yield subject, prediate, and literal to results.
                yield RDF::Statement(object, predicate, subject, graph_name: graph_name, quoted: quoted)
              end
            end
          when '@included'
            values.each do |v|
              item_to_rdf(v, graph_name: graph_name, &block)
            end
          when /^@/
            # Otherwise, if @type is any other keyword, skip to the next property-values pair
          else
            # Otherwise, property is an IRI or Blank Node identifier
            # Initialize predicate from  property as an IRI or Blank node
            predicate = as_resource(property)
            # log_debug("item_to_rdf")  {"predicate: #{predicate.to_ntriples rescue 'malformed rdf'}"}

            # For each item in values
            values.each do |v|
              if list?(v)
                # log_debug("item_to_rdf")  {"list: #{v.inspect}"}
                # If item is a list object, initialize list_results as an empty array, and object to the result of the List Conversion algorithm, passing the value associated with the @list key from item and list_results.
                object = parse_list(v['@list'], graph_name: graph_name, &block)

                # Append a triple composed of subject, prediate, and object to results and add all triples from list_results to results.
              else
                # Otherwise, item is a value object or a node definition. Generate object as the result of the Object Converstion algorithm passing item.
                object = item_to_rdf(v, graph_name: graph_name, &block)
                # log_debug("item_to_rdf")  {"object: #{object.to_ntriples rescue 'malformed rdf'}"}
                # yield subject, prediate, and literal to results.
              end
              yield RDF::Statement(subject, predicate, object, graph_name: graph_name, quoted: quoted)
            end
          end
        end

        subject
      end

      ##
      # Parse a List
      #
      # @param [Array] list
      #   The Array to serialize as a list
      # @yield statement
      # @yieldparam [RDF::Resource] statement
      # @return [Array<RDF::Statement>]
      #   Statements for each item in the list
      def parse_list(list, graph_name: nil, &block)
        # log_debug('parse_list') {"list: #{list.inspect}"}

        last = list.pop
        result = first_bnode = last ? node : RDF.nil

        list.each do |list_item|
          # Set first to the result of the Object Converstion algorithm passing item.
          object = item_to_rdf(list_item, graph_name: graph_name, &block)
          yield RDF::Statement(first_bnode, RDF.first, object, graph_name: graph_name)
          rest_bnode = node
          yield RDF::Statement(first_bnode, RDF.rest, rest_bnode, graph_name: graph_name)
          first_bnode = rest_bnode
        end
        if last
          object = item_to_rdf(last, graph_name: graph_name, &block)
          yield RDF::Statement(first_bnode, RDF.first, object, graph_name: graph_name)
          yield RDF::Statement(first_bnode, RDF.rest, RDF.nil, graph_name: graph_name)
        end
        result
      end

      ##
      # Create a new named node using the sequence
      def node
        RDF::Node.new(namer.get_sym)
      end
    end
  end
end
