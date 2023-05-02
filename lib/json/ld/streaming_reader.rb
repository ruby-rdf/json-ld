# frozen_string_literal: true

require 'json/ld'
require 'json/ld/expand'
require 'json/ld/to_rdf'

module JSON
  module LD
    ##
    # A streaming JSON-LD parser in Ruby.
    #
    # @see http://json-ld.org/spec/ED/20110507/
    # @author [Gregg Kellogg](http://greggkellogg.net/)
    module StreamingReader
      include Utils
      include JSON::LD::ToRDF # For value object conversion

      # The base URI to use when resolving relative URIs
      # @return [RDF::URI]
      attr_reader :base
      attr_reader :namer

      def self.format
        JSON::LD::Format
      end

      ##
      # @see   RDF::Reader#each_statement
      def stream_statement
        unique_bnodes = @options[:unique_bnodes]
        rename_bnodes = @options.fetch(:rename_bnodes, true)
        # FIXME: document loader doesn't stream
        @base = RDF::URI(@options[:base] || base_uri)
        mj_opts = @options.keep_if { |k, v| k != :adapter || MUTLI_JSON_ADAPTERS.include?(v) }
        value = MultiJson.load(@doc, mj_opts)
        context_ref = @options[:expandContext]
        # context_ref = @options.fetch(:expandContext, remote_doc.contextUrl)
        context = Context.parse(context_ref, **@options)

        @namer = if unique_bnodes
          BlankNodeUniqer.new
        else
          (rename_bnodes ? BlankNodeNamer.new("b") : BlankNodeMapper.new)
        end
        # Namer for naming provisional nodes, which may be determined later to be actual
        @provisional_namer = BlankNodeNamer.new("p")

        parse_object(value, nil, context, graph_is_named: false) do |st|
          # Only output reasonably valid triples
          yield(st) if st.to_a.all? { |r| r.is_a?(RDF::Term) && (r.uri? ? r.valid? : true) }
        end
      rescue ::JSON::ParserError, ::JSON::LD::JsonLdError => e
        log_fatal("Failed to parse input document: #{e.message}", exception: RDF::ReaderError)
      end

      private

      # Parse a node object, or array of node objects
      #
      # @param [Array, Hash] input
      # @param [String] active_property
      #   The unexpanded property referencing this object
      # @param [Context] context
      # @param [RDF::Resource] subject referencing this object
      # @param [RDF::URI] predicate the predicate part of the reference
      # @param [Boolean] from_map
      #   Expanding from a map, which could be an `@type` map, so don't clear out context term definitions
      # @param [Boolean] graph_is_named
      #   Use of `@graph` implies a named graph; not true at the top-level.
      # @param [RDF::URI] extra_type from a type map
      # @param [String] language from a language map
      # @param [RDF::Resource] node_id from an id map
      # @return [void]
      def parse_object(input, active_property, context,
                       subject: nil, predicate: nil, from_map: false,
                       extra_type: nil, language: nil, node_id: nil,
                       graph_is_named: true, &block)

        # Skip predicates that look like a BNode
        if predicate.to_s.start_with?('_:')
          warn "[DEPRECATION] Blank Node properties deprecated in JSON-LD 1.1."
          return
        end

        if input.is_a?(Array)
          input.each do |e|
            parse_object(e, active_property, context, subject: subject, predicate: predicate, from_map: from_map,
              &block)
          end
          return
        end

        # Note that we haven't parsed an @id key, so have no subject
        have_id = false
        node_reference = false
        is_list_or_set = false
        node_id ||= RDF::Node.new(@provisional_namer.get_sym)
        # For keeping statements not yet ready to be emitted
        provisional_statements = []
        value_object = {}

        # Use a term-specific context, if defined, based on the non-type-scoped context.
        if active_property && context.term_definitions[active_property]
          property_scoped_context = context.term_definitions[active_property].context
        end

        # Revert any previously type-scoped term definitions, unless this is from a map, a value object or a subject reference
        # FIXME
        if input.is_a?(Hash) && context.previous_context
          expanded_key_map = input.keys.inject({}) do |memo, key|
            memo.merge(key => context.expand_iri(key, vocab: true, as_string: true, base: base))
          end
          revert_context = !from_map &&
                           !expanded_key_map.value?('@value') &&
                           expanded_key_map.values != ['@id']
          context = context.previous_context if revert_context
        end

        # Apply property-scoped context after reverting term-scoped context
        context = context.parse(property_scoped_context, base: base, override_protected: true) unless
          property_scoped_context.nil?

        # Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
        input = context.expand_value(active_property, input, base: base) unless input.is_a?(Hash)

        # Output any type provided from a type map
        provisional_statements << RDF::Statement(node_id, RDF.type, extra_type) if
          extra_type

        # Add statement, either provisionally, or just emit
        add_statement = proc do |st|
          if have_id || st.to_quad.none?(node_id)
            yield(st)
          else
            provisional_statements << st
          end
        end

        # Input is an object (Hash), parse keys in order
        state = :await_context
        input.each do |key, value|
          expanded_key = context.expand_iri(key, base: base, vocab: true)
          case expanded_key
          when '@context'
            unless state == :await_context
              raise JsonLdError::InvalidStreamingKeyOrder,
                "found #{key} in state #{state}"
            end
            context = context.parse(value, base: base)
            state = :await_type
          when '@type'
            # Set the type-scoped context to the context on input, for use later
            unless %i[await_context await_type].include?(state)
              raise JsonLdError::InvalidStreamingKeyOrder,
                "found #{key} in state #{state}"
            end

            type_scoped_context = context
            as_array(value).sort.each do |term|
              unless term.is_a?(String)
                raise JsonLdError::InvalidTypeValue,
                  "value of @type must be a string: #{term.inspect}"
              end
              if type_scoped_context.term_definitions[term]
                term_context = type_scoped_context.term_definitions[term].context
              end
              context = context.parse(term_context, base: base, propagate: false) unless term_context.nil?
              type = type_scoped_context.expand_iri(term,
                base: base,
                documentRelative: true,
                vocab: true)

              # Early terminate for @json
              type = RDF.JSON if type == '@json'
              # Add a provisional statement
              provisional_statements << RDF::Statement(node_id, RDF.type, type)
            end
            state = :await_type
          when '@id'
            if is_list_or_set
              raise JsonLdError::InvalidSetOrListObject,
                "found #{key} in state #{state}"
            end
            unless %i[await_context await_type await_id].include?(state)
              raise JsonLdError::CollidingKeywords,
                "found #{key} in state #{state}"
            end

            # Set our actual id, and use for replacing any provisional statements using our existing node_id, which is provisional
            unless value.is_a?(String)
              raise JsonLdError::InvalidIdValue,
                "value of @id must be a string: #{value.inspect}"
            end
            node_reference = input.keys.length == 1
            expanded_id = context.expand_iri(value, base: base, documentRelative: true)
            next if expanded_id.nil?

            new_node_id = as_resource(expanded_id)
            # Replace and emit any statements including our provisional id with the newly established node (or graph) id
            provisional_statements.each do |st|
              st.subject = new_node_id if st.subject == node_id
              st.object = new_node_id if st.object == node_id
              st.graph_name = new_node_id if st.graph_name == node_id
              yield(st)
            end

            provisional_statements.clear
            have_id = true
            node_id = new_node_id

            # if there's a subject & predicate, emit that statement now
            if subject && predicate
              st = RDF::Statement(subject, predicate, node_id)
              yield(st)
            end
            state = :properties

          when '@direction'
            if state == :properties
              raise JsonLdError::InvalidStreamingKeyOrder,
                "found @direction in state #{state}"
            end
            value_object['@direction'] = value
            state = :await_id
          when '@graph'
            # If `@graph` is at the top level (no `subject`) and value contains no keys other than `@graph` and `@context`, add triples to the default graph
            # Process all graph statements
            parse_object(value, nil, context) do |st|
              # If `@graph` is at the top level (`graph_is_named` is `false`) and input contains no keys other than `@graph` and `@context`, add triples to the default graph
              relevant_keys = input.keys - ['@context', key]
              st.graph_name = node_id unless !graph_is_named && relevant_keys.empty?
              if st.graph_name && !st.graph_name.valid?
                warn "skipping graph statement within invalid graph name: #{st.inspect}"
              else
                add_statement.call(st)
              end
            end
            state = :await_id unless state == :properties
          when '@included'
            # Expanded values must be node objects
            have_statements = false
            parse_object(value, active_property, context) do |st|
              have_statements ||= st.subject?
              yield(st)
            end
            unless have_statements
              raise JsonLdError::InvalidIncludedValue,
                "values of @included must expand to node objects"
            end

            state = :await_id unless state == :properties
          when '@index'
            state = :await_id unless state == :properties
            unless value.is_a?(String)
              raise JsonLdError::InvalidIndexValue,
                "Value of @index is not a string: #{value.inspect}"
            end
          when '@language'
            if state == :properties
              raise JsonLdError::InvalidStreamingKeyOrder,
                "found @language in state #{state}"
            end
            unless value.is_a?(String)
              raise JsonLdError::InvalidLanguageTaggedString,
                "@language value must be a string: #{value.inspect}"
            end
            unless /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(value)
              warn "@language must be valid BCP47: #{value.inspect}"
              return
            end
            language = value
            state = :await_id
          when '@list'
            unless %i[await_context await_type await_id].include?(state)
              raise JsonLdError::InvalidSetOrListObject,
                "found #{key} in state #{state}"
            end
            is_list_or_set = true
            node_id = parse_list(value, active_property, context, &block) if subject
            state = :properties
          when '@nest'
            if context.term_definitions[active_property]
              nest_context = context.term_definitions[active_property].context
            end
            nest_context = if nest_context.nil?
              context
            else
              context.parse(nest_context, base: base, override_protected: true)
            end
            as_array(value).each do |v|
              raise JsonLdError::InvalidNestValue, v.inspect unless
                v.is_a?(Hash) && v.keys.none? { |k| nest_context.expand_iri(k, vocab: true, base: base) == '@value' }

              parse_object(v, active_property, nest_context, node_id: node_id) do |st|
                add_statement.call(st)
              end
            end
            state = :await_id unless state == :properties
          when '@reverse'
            as_array(value).each do |item|
              item = context.expand_value(active_property, item, base: base) unless item.is_a?(Hash)
              raise JsonLdError::InvalidReverseValue, item.inspect if value?(item)
              raise JsonLdError::InvalidReversePropertyMap, item.inspect if node_reference?(item)
              raise JsonLdError::InvalidReversePropertyValue, item.inspect if list?(item)

              has_own_subject = false
              parse_object(item, active_property, context, node_id: node_id, predicate: predicate) do |st|
                if st.subject == node_id
                  raise JsonLdError::InvalidReversePropertyValue, item.inspect unless st.object.resource?

                  # Invert sense of statements
                  st = RDF::Statement(st.object, st.predicate, st.subject)
                  has_own_subject = true
                end
                add_statement.call(st)
              end

              # If the reversed node does not make any claims on this subject, it's an error
              raise JsonLdError::InvalidReversePropertyValue, item.inspect unless has_own_subject
            end
            state = :await_id unless state == :properties
          when '@set'
            unless %i[await_context await_type await_id].include?(state)
              raise JsonLdError::InvalidSetOrListObject,
                "found #{key} in state #{state}"
            end
            is_list_or_set = true
            value = as_array(value).compact
            parse_object(value, active_property, context, subject: subject, predicate: predicate, &block)
            node_id = nil
            state = :properties
          when '@value'
            if state == :properties
              raise JsonLdError::InvalidStreamingKeyOrder,
                "found @value in state #{state}"
            end
            value_object['@value'] = value
            state = :await_id
          else
            state = :await_id unless state == :properties
            # Skip keys that don't expand to a keyword or absolute IRI
            next if expanded_key.is_a?(RDF::URI) && !expanded_key.absolute?

            parse_property(value, key, context, node_id, expanded_key) do |st|
              add_statement.call(st)
            end
          end
        end

        # Value object with @id
        if !value_object.empty? && (have_id || is_list_or_set)
          raise JsonLdError::InvalidValueObject,
            "value object has unknown key: @id"
        end

        # Can't have both @id and either @list or @set
        if have_id && is_list_or_set
          raise JsonLdError::InvalidSetOrListObject,
            "found @id with @list or @set"
        end

        type_statements = provisional_statements.select { |ps| ps.predicate == RDF.type && ps.graph_name.nil? }
        value_object['@language'] = (@options[:lowercaseLanguage] ? language.downcase : language) if language
        if !value_object.empty? &&
           (!value_object['@value'].nil? ||
            (type_statements.first || RDF::Statement.new).object == RDF.JSON)

          # There can be only one value of @type
          case type_statements.length
          when 0 # skip
          when 1
            unless type_statements.first.object.valid?
              raise JsonLdError::InvalidTypedValue,
                "value of @type must be an IRI or '@json': #{type_statements.first.object.inspect}"
            end
            value_object['@type'] = type_statements.first.object
          else
            raise JsonLdError::InvalidValueObject,
              "value object must not have more than one type"
          end

          # Check for extra keys
          unless (value_object.keys - Expand::KEYS_VALUE_LANGUAGE_TYPE_INDEX_DIRECTION).empty?
            raise JsonLdError::InvalidValueObject,
              "value object has unknown keys: #{value_object.inspect}"
          end

          # @type is inconsistent with either @language or @direction
          if value_object.key?('@type') && !(value_object.keys & %w[@language @direction]).empty?
            raise JsonLdError::InvalidValueObject,
              "value object must not include @type with either " \
              "@language or @direction: #{value_object.inspect}"
          end

          if value_object.key?('@language') && !value_object['@value'].is_a?(String)
            raise JsonLdError::InvalidLanguageTaggedValue,
              "with @language @value must be a string: #{value_object.inspect}"
          elsif value_object['@type'] && value_object['@type'] != RDF.JSON
            unless value_object['@type'].is_a?(RDF::URI)
              raise JsonLdError::InvalidTypedValue,
                "value of @type must be an IRI or '@json': #{value_object['@type'].inspect}"
            end
          elsif value_object['@type'] != RDF.JSON
            case value_object['@value']
            when String, TrueClass, FalseClass, Numeric # okay
            else
              raise JsonLdError::InvalidValueObjectValue,
                "@value is: #{value_object['@value'].inspect}"
            end
          end
          literal = item_to_rdf(value_object, &block)
          st = RDF::Statement(subject, predicate, literal)
          yield(st)
        elsif !provisional_statements.empty?
          # Emit all provisional statements, as no @id was ever found
          provisional_statements.each(&block)
        end

        # Use implicit subject to generate the relationship
        return unless value_object.empty? && subject && predicate && !have_id && !node_reference

        yield(RDF::Statement(subject, predicate, node_id))
      end

      def parse_property(input, active_property, context, subject, predicate, &block)
        container = context.container(active_property)
        if container.include?('@language') && input.is_a?(Hash)
          input.each do |lang, lang_value|
            expanded_lang = context.expand_iri(lang, vocab: true)
            if lang !~ /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/ && expanded_lang != '@none'
              warn "@language must be valid BCP47: #{lang.inspect}"
            end

            as_array(lang_value).each do |item|
              unless item.nil? || item.is_a?(String)
                raise JsonLdError::InvalidLanguageMapValue,
                  "Expected #{item.inspect} to be a string"
              end
              lang_obj = { '@value' => item }
              lang_obj['@language'] = lang unless expanded_lang == '@none'
              lang_obj['@direction'] = context.direction(lang) if context.direction(lang)
              parse_object(lang_obj, active_property, context, subject: subject, predicate: predicate, &block)
            end
          end
        elsif container.include?('@list')
          # Handle case where value is a list object
          if input.is_a?(Hash) &&
             input.keys.map do |k|
               context.expand_iri(k, vocab: true, as_string: true, base: base)
             end.include?('@list')
            parse_object(input, active_property, context,
              subject: subject, predicate: predicate, &block)
          else
            list = parse_list(input, active_property, context, &block)
            yield(RDF::Statement(subject, predicate, list))
          end
        elsif container.intersect?(JSON::LD::Expand::CONTAINER_INDEX_ID_TYPE) && input.is_a?(Hash)
          # Get appropriate context for this container
          container_context = if container.include?('@type') && context.previous_context
            context.previous_context
          elsif container.include?('@id') && context.term_definitions[active_property]
            id_context = context.term_definitions[active_property].context if context.term_definitions[active_property]
            if id_context.nil?
              context
            else
              context.parse(id_context, base: base, propagate: false)
            end
          else
            context
          end

          input.each do |k, v|
            # If container mapping in the active context includes @type, and k is a term in the active context having a local context, use that context when expanding values
            map_context = container_context.term_definitions[k].context if
              container.include?('@type') && container_context.term_definitions[k]
            map_context = container_context.parse(map_context, base: base, propagate: false) unless map_context.nil?
            map_context ||= container_context

            expanded_k = container_context.expand_iri(k, vocab: true, as_string: true, base: base)
            index_key = context.term_definitions[active_property].index || '@index'

            if container.include?('@index') && container.include?('@graph')
              # Index is ignored
              as_array(v).each do |item|
                # Each value is in a separate graph
                graph_name = RDF::Node.new(namer.get_sym)
                parse_object(item, active_property, context) do |st|
                  st.graph_name ||= graph_name
                  yield(st)
                end
                yield(RDF::Statement(subject, predicate, graph_name))

                # Add a property index, if appropriate
                next if index_key == '@index'

                # Expand key based on term
                expanded_k = if k == '@none'
                  '@none'
                else
                  container_context.expand_value(index_key, k, base: base)
                end

                # Add the index property as a property of the graph name
                index_property = container_context.expand_iri(index_key, vocab: true, base: base)
                unless expanded_k == '@none'
                  emit_object(expanded_k, index_key, map_context, graph_name,
                    index_property, from_map: true, &block)
                end
              end
            elsif container.include?('@index')
              if index_key == '@index'
                # Index is ignored
                emit_object(v, active_property, map_context, subject, predicate, from_map: true, &block)
              else
                # Expand key based on term
                expanded_k = if k == '@none'
                  '@none'
                else
                  container_context.expand_value(index_key, k, base: base)
                end

                index_property = container_context.expand_iri(index_key, vocab: true, as_string: true, base: base)

                # index_key is a property
                as_array(v).each do |item|
                  item = container_context.expand_value(active_property, item, base: base) if item.is_a?(String)
                  if value?(item)
                    raise JsonLdError::InvalidValueObject,
                      "Attempt to add illegal key to value object: #{index_key}"
                  end
                  # add expanded_k as value of index_property in item
                  item[index_property] = [expanded_k].concat(Array(item[index_property])) unless expanded_k == '@none'
                  emit_object(item, active_property, map_context, subject, predicate, from_map: true, &block)
                end
              end
            elsif container.include?('@id') && container.include?('@graph')
              graph_name = if expanded_k == '@none'
                RDF::Node.new(namer.get_sym)
              else
                container_context.expand_iri(k, documentRelative: true, base: base)
              end
              parse_object(v, active_property, context) do |st|
                st.graph_name ||= graph_name
                yield(st)
              end
              yield(RDF::Statement(subject, predicate, graph_name))
            elsif container.include?('@id')
              expanded_k = container_context.expand_iri(k, documentRelative: true, base: base)
              # pass our id
              emit_object(v, active_property, map_context, subject, predicate,
                node_id: (expanded_k unless expanded_k == '@none'),
                from_map: true,
                &block)
            elsif container.include?('@type')
              emit_object(v, active_property, map_context, subject, predicate,
                from_map: true,
                extra_type: as_resource(expanded_k),
                &block)
            end
          end
        elsif container.include?('@graph')
          # Index is ignored
          as_array(input).each do |v|
            # Each value is in a separate graph
            graph_name = RDF::Node.new(namer.get_sym)
            parse_object(v, active_property, context) do |st|
              st.graph_name ||= graph_name
              yield(st)
            end
            yield(RDF::Statement(subject, predicate, graph_name))
          end
        else
          emit_object(input, active_property, context, subject, predicate, &block)
        end
      end

      # Wrapps parse_object to handle JSON literals and reversed properties
      def emit_object(input, active_property, context, subject, predicate, **options, &block)
        if context.coerce(active_property) == '@json'
          parse_object(context.expand_value(active_property, input), active_property, context,
            subject: subject, predicate: predicate, **options, &block)
        elsif context.reverse?(active_property)
          as_array(input).each do |item|
            item = context.expand_value(active_property, item, base: base) unless item.is_a?(Hash)
            raise JsonLdError::InvalidReverseValue, item.inspect if value?(item)
            raise JsonLdError::InvalidReversePropertyValue, item.inspect if list?(item)

            has_own_subject = false
            parse_object(item, active_property, context, subject: subject, predicate: predicate, **options) do |st|
              if st.subject == subject
                raise JsonLdError::InvalidReversePropertyValue, item.inspect unless st.object.resource?

                # Invert sense of statements
                st = RDF::Statement(st.object, st.predicate, st.subject)
                has_own_subject = true
              end
              yield(st)
            end

            # If the reversed node does not make any claims on this subject, it's an error
            unless has_own_subject
              raise JsonLdError::InvalidReversePropertyValue,
                "@reverse value must be a node: #{value.inspect}"
            end
          end
        else
          as_array(input).flatten.each do |item|
            # emit property/value
            parse_object(item, active_property, context,
              subject: subject, predicate: predicate, **options, &block)
          end
        end
      end

      # Process input as an ordered list
      # @return [RDF::Resource] the list head
      def parse_list(input, active_property, context, &block)
        # Transform all entries into their values
        # this allows us to eliminate those that don't create any statements
        fake_subject = RDF::Node.new
        values = as_array(input).map do |entry|
          if entry.is_a?(Array)
            # recursive list
            entry_value = parse_list(entry, active_property, context, &block)
          else
            entry_value = nil
            parse_object(entry, active_property, context, subject: fake_subject, predicate: RDF.first) do |st|
              if st.subject == fake_subject
                entry_value = st.object
              else
                yield(st)
              end
            end
            entry_value
          end
        end.compact
        return RDF.nil if values.empty?

        # Construct a list from values, and emit list statements, returning the list subject
        list = RDF::List(*values)
        list.each_statement(&block)
        list.subject
      end
    end
  end
end
