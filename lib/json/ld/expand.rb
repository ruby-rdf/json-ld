# frozen_string_literal: true

require 'set'

module JSON
  module LD
    ##
    # Expand module, used as part of API
    module Expand
      include Utils

      # The following constant is used to reduce object allocations
      CONTAINER_INDEX_ID_TYPE = Set['@index', '@id', '@type'].freeze
      KEY_ID = %w[@id].freeze
      KEYS_VALUE_LANGUAGE_TYPE_INDEX_DIRECTION = %w[@value @language @type @index @direction @annotation].freeze
      KEYS_SET_LIST_INDEX = %w[@set @list @index].freeze
      KEYS_INCLUDED_TYPE_REVERSE = %w[@included @type @reverse].freeze

      ##
      # Expand an Array or Object given an active context and performing local context expansion.
      #
      # @param [Array, Hash] input
      # @param [String] active_property
      # @param [Context] context
      # @param [Boolean] framing (false)
      #   Special rules for expanding a frame
      # @param [Boolean] from_map
      #   Expanding from a map, which could be an `@type` map, so don't clear out context term definitions
      #
      # @return [Array<Hash{String => Object}>]
      def expand(input, active_property, context,
                 framing: false, from_map: false, log_depth: nil)
        # log_debug("expand", depth: log_depth.to_i) {"input: #{input.inspect}, active_property: #{active_property.inspect}, context: #{context.inspect}"}
        framing = false if active_property == '@default'
        if active_property
          expanded_active_property = context.expand_iri(active_property, vocab: true, as_string: true,
            base: @options[:base])
        end

        # Use a term-specific context, if defined, based on the non-type-scoped context.
        if active_property && context.term_definitions[active_property]
          property_scoped_context = context.term_definitions[active_property].context
        end
        # log_debug("expand", depth: log_depth.to_i) {"property_scoped_context: #{property_scoped_context.inspect}"} unless property_scoped_context.nil?

        case input
        when Array
          # If element is an array,
          is_list = context.container(active_property).include?('@list')
          input.each_with_object([]) do |v, memo|
            # Initialize expanded item to the result of using this algorithm recursively, passing active context, active property, and item as element.
            v = expand(v, active_property, context,
              framing: framing,
              from_map: from_map,
              log_depth: log_depth.to_i + 1)

            # If the active property is @list or its container mapping is set to @list and v is an array, change it to a list object
            if is_list && v.is_a?(Array)
              # Make sure that no member of v contains an annotation object
              if v.any? { |n| n.is_a?(Hash) && n.key?('@annotation') }
                raise JsonLdError::InvalidAnnotation,
                  "A list element must not contain @annotation."
              end
              v = { "@list" => v }
            end

            case v
            when nil then nil
            when Array then memo.concat(v)
            else            memo << v
            end
          end

        when Hash
          if context.previous_context
            expanded_key_map = input.keys.inject({}) do |memo, key|
              memo.merge(key => context.expand_iri(key, vocab: true, as_string: true, base: @options[:base]))
            end
            # Revert any previously type-scoped term definitions, unless this is from a map, a value object or a subject reference
            revert_context = !from_map &&
                             !expanded_key_map.value?('@value') &&
                             expanded_key_map.values != ['@id']

            # If there's a previous context, the context was type-scoped
            # log_debug("expand", depth: log_depth.to_i) {"previous_context: #{context.previous_context.inspect}"} if revert_context
            context = context.previous_context if revert_context
          end

          # Apply property-scoped context after reverting term-scoped context
          unless property_scoped_context.nil?
            context = context.parse(property_scoped_context, base: @options[:base], override_protected: true)
          end
          # log_debug("expand", depth: log_depth.to_i) {"after property_scoped_context: #{context.inspect}"} unless property_scoped_context.nil?

          # If element contains the key @context, set active context to the result of the Context Processing algorithm, passing active context and the value of the @context key as local context.
          if input.key?('@context')
            context = context.parse(input['@context'], base: @options[:base])
            # log_debug("expand", depth: log_depth.to_i) {"context: #{context.inspect}"}
          end

          # Set the type-scoped context to the context on input, for use later
          type_scoped_context = context

          output_object = {}

          # See if keys mapping to @type have terms with a local context
          type_key = nil
          (input.keys - %w[@context]).sort
            .select { |k| context.expand_iri(k, vocab: true, base: @options[:base]) == '@type' }
            .each do |tk|
            type_key ||= tk # Side effect saves the first found key mapping to @type
            Array(input[tk]).sort.each do |term|
              if type_scoped_context.term_definitions[term]
                term_context = type_scoped_context.term_definitions[term].context
              end
              unless term_context.nil?
                # log_debug("expand", depth: log_depth.to_i) {"term_context[#{term}]: #{term_context.inspect}"}
                context = context.parse(term_context, base: @options[:base], propagate: false)
              end
            end
          end

          # Process each key and value in element. Ignores @nesting content
          expand_object(input, active_property, context, output_object,
            expanded_active_property: expanded_active_property,
            framing: framing,
            type_key: type_key,
            type_scoped_context: type_scoped_context,
            log_depth: log_depth.to_i + 1)

          # log_debug("output object", depth: log_depth.to_i) {output_object.inspect}

          # If result contains the key @value:
          if value?(output_object)
            keys = output_object.keys
            unless (keys - KEYS_VALUE_LANGUAGE_TYPE_INDEX_DIRECTION).empty?
              # The result must not contain any keys other than @direction, @value, @language, @type, and @index. It must not contain both the @language key and the @type key. Otherwise, an invalid value object error has been detected and processing is aborted.
              raise JsonLdError::InvalidValueObject,
                "value object has unknown keys: #{output_object.inspect}"
            end

            if keys.include?('@type') && !(keys & %w[@language @direction]).empty?
              # @type is inconsistent with either @language or @direction
              raise JsonLdError::InvalidValueObject,
                "value object must not include @type with either @language or @direction: #{output_object.inspect}"
            end

            if output_object.key?('@language') && Array(output_object['@language']).empty?
              output_object.delete('@language')
            end
            type_is_json = output_object['@type'] == '@json'
            output_object.delete('@type') if output_object.key?('@type') && Array(output_object['@type']).empty?

            # If the value of result's @value key is null, then set result to null and @type is not @json.
            ary = Array(output_object['@value'])
            return nil if ary.empty? && !type_is_json

            if output_object['@type'] == '@json' && context.processingMode('json-ld-1.1')
              # Any value of @value is okay if @type: @json
            elsif !ary.all? { |v| v.is_a?(String) || (v.is_a?(Hash) && v.empty?) } && output_object.key?('@language')
              # Otherwise, if the value of result's @value member is not a string and result contains the key @language, an invalid language-tagged value error has been detected (only strings can be language-tagged) and processing is aborted.
              raise JsonLdError::InvalidLanguageTaggedValue,
                "when @language is used, @value must be a string: #{output_object.inspect}"
            elsif output_object['@type'] &&
                  (!Array(output_object['@type']).all? do |t|
                     (t.is_a?(String) && RDF::URI(t).valid? && !t.start_with?('_:')) ||
                     (t.is_a?(Hash) && t.empty?)
                   end ||
                   (!framing && !output_object['@type'].is_a?(String)))
              # Otherwise, if the result has a @type member and its value is not an IRI, an invalid typed value error has been detected and processing is aborted.
              raise JsonLdError::InvalidTypedValue,
                "value of @type must be an IRI or '@json': #{output_object.inspect}"
            elsif !framing && !output_object.fetch('@type', '').is_a?(String) &&
                  RDF::URI(t).valid? && !t.start_with?('_:')
              # Otherwise, if the result has a @type member and its value is not an IRI, an invalid typed value error has been detected and processing is aborted.
              raise JsonLdError::InvalidTypedValue,
                "value of @type must be an IRI or '@json': #{output_object.inspect}"
            end
          elsif !output_object.fetch('@type', []).is_a?(Array)
            # Otherwise, if result contains the key @type and its associated value is not an array, set it to an array containing only the associated value.
            output_object['@type'] = [output_object['@type']]
          elsif output_object.key?('@set') || output_object.key?('@list')
            # Otherwise, if result contains the key @set or @list:
            # The result must contain at most one other key and that key must be @index. Otherwise, an invalid set or list object error has been detected and processing is aborted.
            unless (output_object.keys - KEYS_SET_LIST_INDEX).empty?
              raise JsonLdError::InvalidSetOrListObject,
                "@set or @list may only contain @index: #{output_object.keys.inspect}"
            end

            # If result contains the key @set, then set result to the key's associated value.
            return output_object['@set'] if output_object.key?('@set')
          elsif output_object['@annotation']
            # Otherwise, if result contains the key @annotation,
            # the array value must all be node objects without an @id property, otherwise, an invalid annotation error has been detected and processing is aborted.
            unless output_object['@annotation'].all? { |o| node?(o) && !o.key?('@id') }
              raise JsonLdError::InvalidAnnotation,
                "@annotation must reference node objects without @id."
            end

            # Additionally, the property must not be used if there is no active property, or the expanded active property is @graph.
            if %w[@graph @included].include?(expanded_active_property || '@graph')
              raise JsonLdError::InvalidAnnotation,
                "@annotation must not be used on a top-level object."
            end

          end

          # If result contains only the key @language, set result to null.
          return nil if output_object.length == 1 && output_object.key?('@language')

          # If active property is null or @graph, drop free-floating values as follows:
          if (expanded_active_property || '@graph') == '@graph' &&
             (output_object.key?('@value') || output_object.key?('@list') ||
             ((output_object.keys - KEY_ID).empty? && !framing))
            # log_debug(" =>", depth: log_depth.to_i) { "empty top-level: " + output_object.inspect}
            return nil
          end

          # Re-order result keys if ordering
          if @options[:ordered]
            output_object.keys.sort.each_with_object({}) { |kk, memo| memo[kk] = output_object[kk] }
          else
            output_object
          end
        else
          # Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
          return nil if input.nil? || active_property.nil? || expanded_active_property == '@graph'

          # Apply property-scoped context
          unless property_scoped_context.nil?
            context = context.parse(property_scoped_context,
              base: @options[:base],
              override_protected: true)
          end
          # log_debug("expand", depth: log_depth.to_i) {"property_scoped_context: #{context.inspect}"} unless property_scoped_context.nil?

          context.expand_value(active_property, input, base: @options[:base])
        end

        # log_debug(depth: log_depth.to_i) {" => #{result.inspect}"}
      end

      private

      # Expand each key and value of element adding them to result
      def expand_object(input, active_property, context, output_object,
                        expanded_active_property:,
                        framing:,
                        type_key:,
                        type_scoped_context:,
                        log_depth: nil)
        nests = []

        input_type = Array(input[type_key]).last
        input_type = context.expand_iri(input_type, vocab: true, as_string: true, base: @options[:base]) if input_type

        # Then, proceed and process each property and value in element as follows:
        keys = @options[:ordered] ? input.keys.sort : input.keys
        keys.each do |key|
          # For each key and value in element, ordered lexicographically by key:
          value = input[key]
          expanded_property = context.expand_iri(key, vocab: true, base: @options[:base])

          # If expanded property is null or it neither contains a colon (:) nor it is a keyword, drop key by continuing to the next key.
          next if expanded_property.is_a?(RDF::URI) && expanded_property.relative?

          expanded_property = expanded_property.to_s if expanded_property.is_a?(RDF::Resource)

          warn "[DEPRECATION] Blank Node properties deprecated in JSON-LD 1.1." if
            @options[:validate] &&
            expanded_property.to_s.start_with?("_:") &&
            context.processingMode('json-ld-1.1')

          # log_debug("expand property", depth: log_depth.to_i) {"ap: #{active_property.inspect}, expanded: #{expanded_property.inspect}, value: #{value.inspect}"}

          if expanded_property.nil?
            # log_debug(" => ", depth: log_depth.to_i) {"skip nil property"}
            next
          end

          if KEYWORDS.include?(expanded_property)
            # If active property equals @reverse, an invalid reverse property map error has been detected and processing is aborted.
            if expanded_active_property == '@reverse'
              raise JsonLdError::InvalidReversePropertyMap,
                "@reverse not appropriate at this point"
            end

            # If result has already an expanded property member (other than @type), an colliding keywords error has been detected and processing is aborted.
            if output_object.key?(expanded_property) && !KEYS_INCLUDED_TYPE_REVERSE.include?(expanded_property)
              raise JsonLdError::CollidingKeywords,
                "#{expanded_property} already exists in result"
            end

            expanded_value = case expanded_property
            when '@id'
              # If expanded active property is `@annotation`, an invalid annotation error has been found and processing is aborted.
              if expanded_active_property == '@annotation' && @options[:rdfstar]
                raise JsonLdError::InvalidAnnotation,
                  "an annotation must not contain a property expanding to @id"
              end

              # If expanded property is @id and value is not a string, an invalid @id value error has been detected and processing is aborted
              e_id = case value
              when String
                context.expand_iri(value, as_string: true, base: @options[:base], documentRelative: true)
              when Array
                # Framing allows an array of IRIs, and always puts values in an array
                unless framing
                  raise JsonLdError::InvalidIdValue,
                    "value of @id must be a string unless framing: #{value.inspect}"
                end
                context.expand_iri(value, as_string: true, base: @options[:base], documentRelative: true)
                value.map do |v|
                  unless v.is_a?(String)
                    raise JsonLdError::InvalidTypeValue,
                      "@id value must be a string or array of strings for framing: #{v.inspect}"
                  end
                  context.expand_iri(v, as_string: true, base: @options[:base], documentRelative: true)
                end
              when Hash
                if framing
                  unless value.empty?
                    raise JsonLdError::InvalidTypeValue,
                      "value of @id must be a an empty object for framing: #{value.inspect}"
                  end
                  [{}]
                elsif @options[:rdfstar]
                  # Result must have just a single statement
                  rei_node = expand(value, nil, context, log_depth: log_depth.to_i + 1)

                  # Node must not contain @reverse
                  if rei_node&.key?('@reverse')
                    raise JsonLdError::InvalidEmbeddedNode,
                      "Embedded node with @reverse"
                  end
                  statements = to_enum(:item_to_rdf, rei_node)
                  unless statements.count == 1
                    raise JsonLdError::InvalidEmbeddedNode,
                      "Embedded node with #{statements.size} statements"
                  end
                  rei_node
                else
                  unless framing
                    raise JsonLdError::InvalidIdValue,
                      "value of @id must be a string unless framing: #{value.inspect}"
                  end
                end
              else
                raise JsonLdError::InvalidIdValue,
                  "value of @id must be a string or hash if framing: #{value.inspect}"
              end

              # Use array form if framing
              if framing
                as_array(e_id)
              else
                e_id
              end
            when '@included'
              # Included blocks are treated as an array of separate object nodes sharing the same referencing active_property. For 1.0, it is skipped as are other unknown keywords
              next if context.processingMode('json-ld-1.0')

              included_result = as_array(expand(value, active_property, context,
                framing: framing,
                log_depth: log_depth.to_i + 1))

              # Expanded values must be node objects
              unless included_result.all? do |e|
                       node?(e)
                     end
                raise JsonLdError::InvalidIncludedValue,
                  "values of @included must expand to node objects"
              end

              # As other properties may alias to @included, add this to any other previously expanded values
              Array(output_object['@included']) + included_result
            when '@type'
              # If expanded property is @type and value is neither a string nor an array of strings, an invalid type value error has been detected and processing is aborted. Otherwise, set expanded value to the result of using the IRI Expansion algorithm, passing active context, true for vocab, and true for document relative to expand the value or each of its items.
              # log_debug("@type", depth: log_depth.to_i) {"value: #{value.inspect}"}
              e_type = case value
              when Array
                value.map do |v|
                  unless v.is_a?(String)
                    raise JsonLdError::InvalidTypeValue,
                      "@type value must be a string or array of strings: #{v.inspect}"
                  end
                  type_scoped_context.expand_iri(v,
                    as_string: true,
                    base: @options[:base],
                    documentRelative: true,
                    vocab: true)
                end
              when String
                type_scoped_context.expand_iri(value,
                  as_string: true,
                  base: @options[:base],
                  documentRelative: true,
                  vocab: true)
              when Hash
                if !framing
                  raise JsonLdError::InvalidTypeValue,
                    "@type value must be a string or array of strings: #{value.inspect}"
                elsif value.keys.length == 1 &&
                      type_scoped_context.expand_iri(value.keys.first, vocab: true, base: @options[:base]) == '@default'
                  # Expand values of @default, which must be a string, or array of strings expanding to IRIs
                  [{ '@default' => Array(value['@default']).map do |v|
                    unless v.is_a?(String)
                      raise JsonLdError::InvalidTypeValue,
                        "@type default value must be a string or array of strings: #{v.inspect}"
                    end
                    type_scoped_context.expand_iri(v,
                      as_string: true,
                      base: @options[:base],
                      documentRelative: true,
                      vocab: true)
                  end }]
                elsif !value.empty?
                  raise JsonLdError::InvalidTypeValue,
                    "@type value must be a an empty object for framing: #{value.inspect}"
                else
                  [{}]
                end
              else
                raise JsonLdError::InvalidTypeValue,
                  "@type value must be a string or array of strings: #{value.inspect}"
              end

              e_type = Array(output_object['@type']) + Array(e_type)
              # Use array form if framing
              framing || e_type.length > 1 ? e_type : e_type.first
            when '@graph'
              # If expanded property is @graph, set expanded value to the result of using this algorithm recursively passing active context, @graph for active property, and value for element.
              value = expand(value, '@graph', context,
                framing: framing,
                log_depth: log_depth.to_i + 1)
              as_array(value)
            when '@value'
              # If expanded property is @value and input contains @type: json, accept any value.
              # If expanded property is @value and value is not a scalar or null, an invalid value object value error has been detected and processing is aborted. (In 1.1, @value can have any JSON value of @type is @json or the property coerces to @json).
              # Otherwise, set expanded value to value. If expanded value is null, set the @value member of result to null and continue with the next key from element. Null values need to be preserved in this case as the meaning of an @type member depends on the existence of an @value member.
              # If framing, always use array form, unless null
              if input_type == '@json' && context.processingMode('json-ld-1.1')
                value
              else
                case value
                when String, TrueClass, FalseClass, Numeric then (framing ? [value] : value)
                when nil
                  output_object['@value'] = nil
                  next
                when Array
                  unless framing
                    raise JsonLdError::InvalidValueObjectValue,
                      "@value value may not be an array unless framing: #{value.inspect}"
                  end
                  value
                when Hash
                  unless value.empty? && framing
                    raise JsonLdError::InvalidValueObjectValue,
                      "@value value must be a an empty object for framing: #{value.inspect}"
                  end
                  [value]
                else
                  raise JsonLdError::InvalidValueObjectValue,
                    "Value of #{expanded_property} must be a scalar or null: #{value.inspect}"
                end
              end
            when '@language'
              # If expanded property is @language and value is not a string, an invalid language-tagged string error has been detected and processing is aborted. Otherwise, set expanded value to lowercased value.
              # If framing, always use array form, unless null
              case value
              when String
                unless /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(value)
                  warn "@language must be valid BCP47: #{value.inspect}"
                end
                if @options[:lowercaseLanguage]
                  (framing ? [value.downcase] : value.downcase)
                else
                  (framing ? [value] : value)
                end
              when Array
                unless framing
                  raise JsonLdError::InvalidLanguageTaggedString,
                    "@language value may not be an array unless framing: #{value.inspect}"
                end
                value.each do |v|
                  unless /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(v)
                    warn "@language must be valid BCP47: #{v.inspect}"
                  end
                end
                @options[:lowercaseLanguage] ? value.map(&:downcase) : value
              when Hash
                unless value.empty? && framing
                  raise JsonLdError::InvalidLanguageTaggedString,
                    "@language value must be a an empty object for framing: #{value.inspect}"
                end
                [value]
              else
                raise JsonLdError::InvalidLanguageTaggedString,
                  "Value of #{expanded_property} must be a string: #{value.inspect}"
              end
            when '@direction'
              # If expanded property is @direction and value is not either 'ltr' or 'rtl', an invalid base direction error has been detected and processing is aborted. Otherwise, set expanded value to value.
              # If framing, always use array form, unless null
              case value
              when 'ltr', 'rtl' then (framing ? [value] : value)
              when Array
                unless framing
                  raise JsonLdError::InvalidBaseDirection,
                    "@direction value may not be an array unless framing: #{value.inspect}"
                end
                unless value.all? do |v|
                         %w[
                           ltr rtl
                         ].include?(v) || (v.is_a?(Hash) && v.empty?)
                       end
                  raise JsonLdError::InvalidBaseDirection,
                    "@direction must be one of 'ltr', 'rtl', or an array of those if framing #{value.inspect}"
                end
                value
              when Hash
                unless value.empty? && framing
                  raise JsonLdError::InvalidBaseDirection,
                    "@direction value must be a an empty object for framing: #{value.inspect}"
                end
                [value]
              else
                raise JsonLdError::InvalidBaseDirection,
                  "Value of #{expanded_property} must be one of 'ltr' or 'rtl': #{value.inspect}"
              end
            when '@index'
              # If expanded property is @index and value is not a string, an invalid @index value error has been detected and processing is aborted. Otherwise, set expanded value to value.
              unless value.is_a?(String)
                raise JsonLdError::InvalidIndexValue,
                  "Value of @index is not a string: #{value.inspect}"
              end
              value
            when '@list'
              # If expanded property is @graph:

              # If active property is null or @graph, continue with the next key from element to remove the free-floating list.
              next if (expanded_active_property || '@graph') == '@graph'

              # Otherwise, initialize expanded value to the result of using this algorithm recursively passing active context, active property, and value for element.
              value = expand(value, active_property, context,
                framing: framing,
                log_depth: log_depth.to_i + 1)

              # Spec FIXME: need to be sure that result is an array
              value = as_array(value)

              # Make sure that no member of value contains an annotation object
              if value.any? { |n| n.is_a?(Hash) && n.key?('@annotation') }
                raise JsonLdError::InvalidAnnotation,
                  "A list element must not contain @annotation."
              end

              value
            when '@set'
              # If expanded property is @set, set expanded value to the result of using this algorithm recursively, passing active context, active property, and value for element.
              expand(value, active_property, context,
                framing: framing,
                log_depth: log_depth.to_i + 1)
            when '@reverse'
              # If expanded property is @reverse and value is not a JSON object, an invalid @reverse value error has been detected and processing is aborted.
              unless value.is_a?(Hash)
                raise JsonLdError::InvalidReverseValue,
                  "@reverse value must be an object: #{value.inspect}"
              end

              # Otherwise
              # Initialize expanded value to the result of using this algorithm recursively, passing active context, @reverse as active property, and value as element.
              value = expand(value, '@reverse', context,
                framing: framing,
                log_depth: log_depth.to_i + 1)

              # If expanded value contains an @reverse member, i.e., properties that are reversed twice, execute for each of its property and item the following steps:
              if value.key?('@reverse')
                # log_debug("@reverse", depth: log_depth.to_i) {"double reverse: #{value.inspect}"}
                value['@reverse'].each do |property, item|
                  # If result does not have a property member, create one and set its value to an empty array.
                  # Append item to the value of the property member of result.
                  (output_object[property] ||= []).concat([item].flatten.compact)
                end
              end

              # If expanded value contains members other than @reverse:
              if !value.key?('@reverse') || value.length > 1
                # If result does not have an @reverse member, create one and set its value to an empty JSON object.
                reverse_map = output_object['@reverse'] ||= {}
                value.each do |property, items|
                  next if property == '@reverse'

                  items.each do |item|
                    if value?(item) || list?(item)
                      raise JsonLdError::InvalidReversePropertyValue,
                        item.inspect
                    end
                    merge_value(reverse_map, property, item)
                  end
                end
              end

              # Continue with the next key from element
              next
            when '@default', '@embed', '@explicit', '@omitDefault', '@preserve', '@requireAll'
              next unless framing

              # Framing keywords
              [expand(value, expanded_property, context,
                framing: framing,
                log_depth: log_depth.to_i + 1)].flatten
            when '@nest'
              # Add key to nests
              nests << key
              # Continue with the next key from element
              next
            when '@annotation'
              # Skip unless rdfstar option is set
              next unless @options[:rdfstar]

              as_array(expand(value, '@annotation', context,
                framing: framing,
                log_depth: log_depth.to_i + 1))
            else
              # Skip unknown keyword
              next
            end

            # Unless expanded value is null, set the expanded property member of result to expanded value.
            # log_debug("expand #{expanded_property}", depth: log_depth.to_i) { expanded_value.inspect}
            unless expanded_value.nil? && expanded_property == '@value' && input_type != '@json'
              output_object[expanded_property] =
                expanded_value
            end
            next
          end

          container = context.container(key)
          expanded_value = if context.coerce(key) == '@json'
            # In JSON-LD 1.1, values can be native JSON
            { "@value" => value, "@type" => "@json" }
          elsif container.include?('@language') && value.is_a?(Hash)
            # Otherwise, if key's container mapping in active context is @language and value is a JSON object then value is expanded from a language map as follows:

            # Set multilingual array to an empty array.
            ary = []

            # For each key-value pair language-language value in value, ordered lexicographically by language
            keys = @options[:ordered] ? value.keys.sort : value.keys
            keys.each do |k|
              expanded_k = context.expand_iri(k, vocab: true, as_string: true, base: @options[:base])

              if k !~ /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/ && expanded_k != '@none'
                warn "@language must be valid BCP47: #{k.inspect}"
              end

              [value[k]].flatten.each do |item|
                # item must be a string, otherwise an invalid language map value error has been detected and processing is aborted.
                unless item.nil? || item.is_a?(String)
                  raise JsonLdError::InvalidLanguageMapValue,
                    "Expected #{item.inspect} to be a string"
                end

                # Append a JSON object to expanded value that consists of two key-value pairs: (@value-item) and (@language-lowercased language).
                v = { '@value' => item }
                v['@language'] = (@options[:lowercaseLanguage] ? k.downcase : k) unless expanded_k == '@none'
                v['@direction'] = context.direction(key) if context.direction(key)
                ary << v if item
              end
            end

            ary
          elsif container.intersect?(CONTAINER_INDEX_ID_TYPE) && value.is_a?(Hash)
            # Otherwise, if key's container mapping in active context contains @index, @id, @type and value is a JSON object then value is expanded from an index map as follows:

            # Set ary to an empty array.
            ary = []
            index_key = context.term_definitions[key].index || '@index'

            # While processing index keys, if container includes @type, clear type-scoped term definitions
            container_context = if container.include?('@type') && context.previous_context
              context.previous_context
            elsif container.include?('@id') && context.term_definitions[key]
              id_context = context.term_definitions[key].context if context.term_definitions[key]
              if id_context.nil?
                context
              else
                # log_debug("expand", depth: log_depth.to_i) {"id_context: #{id_context.inspect}"}
                context.parse(id_context, base: @options[:base], propagate: false)
              end
            else
              context
            end

            # For each key-value in the object:
            keys = @options[:ordered] ? value.keys.sort : value.keys
            keys.each do |k|
              # If container mapping in the active context includes @type, and k is a term in the active context having a local context, use that context when expanding values
              if container.include?('@type') && container_context.term_definitions[k]
                map_context = container_context.term_definitions[k].context
              end
              unless map_context.nil?
                # log_debug("expand", depth: log_depth.to_i) {"map_context: #{map_context.inspect}"}
                map_context = container_context.parse(map_context, base: @options[:base],
                  propagate: false)
              end
              map_context ||= container_context

              expanded_k = container_context.expand_iri(k, vocab: true, as_string: true, base: @options[:base])

              # Initialize index value to the result of using this algorithm recursively, passing active context, key as active property, and index value as element.
              index_value = expand([value[k]].flatten, key, map_context,
                framing: framing,
                from_map: true,
                log_depth: log_depth.to_i + 1)
              index_value.each do |item|
                if container.include?('@index')
                  # Indexed graph by graph name
                  item = { '@graph' => as_array(item) } if !graph?(item) && container.include?('@graph')
                  if index_key == '@index'
                    item['@index'] ||= k unless expanded_k == '@none'
                  elsif value?(item)
                    raise JsonLdError::InvalidValueObject, "Attempt to add illegal key to value object: #{index_key}"
                  else
                    # Expand key based on term
                    expanded_k = if k == '@none'
                      '@none'
                    else
                      container_context.expand_value(index_key, k,
                        base: @options[:base])
                    end
                    index_property = container_context.expand_iri(index_key, vocab: true, as_string: true,
                      base: @options[:base])
                    item[index_property] = [expanded_k].concat(Array(item[index_property])) unless expanded_k == '@none'
                  end
                elsif container.include?('@id')
                  # Indexed graph by graph name
                  item = { '@graph' => as_array(item) } if !graph?(item) && container.include?('@graph')
                  # Expand k document relative
                  unless expanded_k == '@none'
                    expanded_k = container_context.expand_iri(k, as_string: true, base: @options[:base],
                      documentRelative: true)
                  end
                  item['@id'] ||= expanded_k unless expanded_k == '@none'
                elsif container.include?('@type')
                  item['@type'] = [expanded_k].concat(Array(item['@type'])) unless expanded_k == '@none'
                end

                # Append item to expanded value.
                ary << item
              end
            end
            ary
          else
            # Otherwise, initialize expanded value to the result of using this algorithm recursively, passing active context, key for active property, and value for element.
            expand(value, key, context,
              framing: framing,
              log_depth: log_depth.to_i + 1)
          end

          # If expanded value is null, ignore key by continuing to the next key from element.
          if expanded_value.nil?
            # log_debug(" => skip nil value", depth: log_depth.to_i)
            next
          end

          # log_debug(depth: log_depth.to_i) {" => #{expanded_value.inspect}"}

          # If the container mapping associated to key in active context is @list and expanded value is not already a list object, convert expanded value to a list object by first setting it to an array containing only expanded value if it is not already an array, and then by setting it to a JSON object containing the key-value pair @list-expanded value.
          if container.first == '@list' && container.length == 1 && !list?(expanded_value)
            # log_debug(" => ", depth: log_depth.to_i) { "convert #{expanded_value.inspect} to list"}
            expanded_value = { '@list' => as_array(expanded_value) }
          end
          # log_debug(depth: log_depth.to_i) {" => #{expanded_value.inspect}"}

          # convert expanded value to @graph if container specifies it
          if container.first == '@graph' && container.length == 1
            # log_debug(" => ", depth: log_depth.to_i) { "convert #{expanded_value.inspect} to list"}
            expanded_value = as_array(expanded_value).map do |v|
              { '@graph' => as_array(v) }
            end
          end

          # Otherwise, if the term definition associated to key indicates that it is a reverse property
          # Spec FIXME: this is not an otherwise.
          if (td = context.term_definitions[key]) && td.reverse_property
            # If result has no @reverse member, create one and initialize its value to an empty JSON object.
            reverse_map = output_object['@reverse'] ||= {}
            [expanded_value].flatten.each do |item|
              # If item is a value object or list object, an invalid reverse property value has been detected and processing is aborted.
              if value?(item) || list?(item)
                raise JsonLdError::InvalidReversePropertyValue,
                  item.inspect
              end

              # If reverse map has no expanded property member, create one and initialize its value to an empty array.
              # Append item to the value of the expanded property member of reverse map.
              merge_value(reverse_map, expanded_property, item)
            end
          else
            # Otherwise, if key is not a reverse property:
            # If result does not have an expanded property member, create one and initialize its value to an empty array.
            (output_object[expanded_property] ||= []).tap do |memo|
              # expanded_value is either Array[Hash] or Hash; in both case append to memo without flatten
              if expanded_value.is_a?(Array)
                memo.concat(expanded_value)
              else # Hash
                memo << expanded_value
              end
            end
          end
        end

        # For each key in nests, recusively expand content
        nests.each do |key|
          nest_context = context.term_definitions[key].context if context.term_definitions[key]
          nest_context = if nest_context.nil?
            context
          else
            # log_debug("expand", depth: log_depth.to_i) {"nest_context: #{nest_context.inspect}"}
            context.parse(nest_context, base: @options[:base],
              override_protected: true)
          end
          nested_values = as_array(input[key])
          nested_values.each do |nv|
            raise JsonLdError::InvalidNestValue, nv.inspect unless
              nv.is_a?(Hash) && nv.keys.none? do |k|
                nest_context.expand_iri(k, vocab: true, base: @options[:base]) == '@value'
              end

            expand_object(nv, active_property, nest_context, output_object,
              framing: framing,
              expanded_active_property: expanded_active_property,
              type_key: type_key,
              type_scoped_context: type_scoped_context,
              log_depth: log_depth.to_i + 1)
          end
        end
      end
    end
  end
end
