module JSON::LD
  ##
  # Expand module, used as part of API
  module Expand
    include Utils

    ##
    # Expand an Array or Object given an active context and performing local context expansion.
    #
    # @param [Array, Hash] input
    # @param [String] active_property
    # @param [Context] context
    # @param [Hash{Symbol => Object}] options
    # @option options [Boolean] :ordered (true)
    #   Ensure output objects have keys ordered properly
    # @return [Array, Hash]
    def expand(input, active_property, context, options = {})
      options = {ordered: true}.merge(options)
      debug("expand") {"input: #{input.inspect}, active_property: #{active_property.inspect}, context: #{context.inspect}"}
      result = case input
      when Array
        # If element is an array,
        depth do
          is_list = context.container(active_property) == '@list'
          value = input.map do |v|
            # Initialize expanded item to the result of using this algorithm recursively, passing active context, active property, and item as element.
            v = expand(v, active_property, context, options)

            # If the active property is @list or its container mapping is set to @list, the expanded item must not be an array or a list object, otherwise a list of lists error has been detected and processing is aborted.
            raise JsonLdError::ListOfLists,
                  "A list may not contain another list" if
                  is_list && (v.is_a?(Array) || list?(v))
            v
          end.flatten.compact

          value
        end
      when Hash
        # If element contains the key @context, set active context to the result of the Context Processing algorithm, passing active context and the value of the @context key as local context.
        if input.has_key?('@context')
          context = context.parse(input.delete('@context'))
          debug("expand") {"context: #{context.inspect}"}
        end

        depth do
          output_object = {}
          # Then, proceed and process each property and value in element as follows:
          keys = options[:ordered] ? input.keys.kw_sort : input.keys
          keys.each do |key|
            # For each key and value in element, ordered lexicographically by key:
            value = input[key]
            expanded_property = context.expand_iri(key, vocab: true, depth: @depth)

            # If expanded property is null or it neither contains a colon (:) nor it is a keyword, drop key by continuing to the next key.
            next if expanded_property.is_a?(RDF::URI) && expanded_property.relative?
            expanded_property = expanded_property.to_s if expanded_property.is_a?(RDF::Resource)

            debug("expand property") {"ap: #{active_property.inspect}, expanded: #{expanded_property.inspect}, value: #{value.inspect}"}

            if expanded_property.nil?
              debug(" => ") {"skip nil property"}
              next
            end

            if KEYWORDS.include?(expanded_property)
              # If active property equals @reverse, an invalid reverse property map error has been detected and processing is aborted.
              raise JsonLdError::InvalidReversePropertyMap,
                    "@reverse not appropriate at this point" if active_property == '@reverse'

              # If result has already an expanded property member, an colliding keywords error has been detected and processing is aborted.
              raise JsonLdError::CollidingKeywords,
                    "#{expanded_property} already exists in result" if output_object.has_key?(expanded_property)

              expanded_value = case expanded_property
              when '@id'
                # If expanded property is @id and value is not a string, an invalid @id value error has been detected and processing is aborted
                raise JsonLdError::InvalidIdValue,
                      "value of @id must be a string: #{value.inspect}" unless value.is_a?(String)

                # Otherwise, set expanded value to the result of using the IRI Expansion algorithm, passing active context, value, and true for document relative.
                context.expand_iri(value, documentRelative: true, depth: @depth).to_s
              when '@type'
                # If expanded property is @type and value is neither a string nor an array of strings, an invalid type value error has been detected and processing is aborted. Otherwise, set expanded value to the result of using the IRI Expansion algorithm, passing active context, true for vocab, and true for document relative to expand the value or each of its items.
                debug("@type") {"value: #{value.inspect}"}
                case value
                when Array
                  depth do
                    value.map do |v|
                      raise JsonLdError::InvalidTypeValue,
                            "@type value must be a string or array of strings: #{v.inspect}" unless v.is_a?(String)
                      context.expand_iri(v, vocab: true, documentRelative: true, quiet: true, depth: @depth).to_s
                    end
                  end
                when String
                  context.expand_iri(value, vocab: true, documentRelative: true, quiet: true, depth: @depth).to_s
                when Hash
                  # For framing
                  raise JsonLdError::InvalidTypeValue,
                        "@type value must be a an empty object for framing: #{value.inspect}" unless
                        value.empty?
                else
                  raise JsonLdError::InvalidTypeValue,
                        "@type value must be a string or array of strings: #{value.inspect}"
                end
              when '@graph'
                # If expanded property is @graph, set expanded value to the result of using this algorithm recursively passing active context, @graph for active property, and value for element.
                depth { expand(value, '@graph', context, options) }
              when '@value'
                # If expanded property is @value and value is not a scalar or null, an invalid value object value error has been detected and processing is aborted. Otherwise, set expanded value to value. If expanded value is null, set the @value member of result to null and continue with the next key from element. Null values need to be preserved in this case as the meaning of an @type member depends on the existence of an @value member.
                raise JsonLdError::InvalidValueObjectValue,
                      "Value of #{expanded_property} must be a scalar or null: #{value.inspect}" if value.is_a?(Hash) || value.is_a?(Array)
                if value.nil?
                  output_object['@value'] = nil
                  next;
                end
                value
              when '@language'
                # If expanded property is @language and value is not a string, an invalid language-tagged string error has been detected and processing is aborted. Otherwise, set expanded value to lowercased value.
                raise JsonLdError::InvalidLanguageTaggedString,
                      "Value of #{expanded_property} must be a string: #{value.inspect}" unless value.is_a?(String)
                value.downcase
              when '@index'
                # If expanded property is @index and value is not a string, an invalid @index value error has been detected and processing is aborted. Otherwise, set expanded value to value.
                raise JsonLdError::InvalidIndexValue,
                      "Value of @index is not a string: #{value.inspect}" unless value.is_a?(String)
                value
              when '@list'
                # If expanded property is @list:

                # If active property is null or @graph, continue with the next key from element to remove the free-floating list.
                next if (active_property || '@graph') == '@graph'

                # Otherwise, initialize expanded value to the result of using this algorithm recursively passing active context, active property, and value for element.
                value = depth { expand(value, active_property, context, options) }

                # Spec FIXME: need to be sure that result is an array
                value = [value] unless value.is_a?(Array)

                # If expanded value is a list object, a list of lists error has been detected and processing is aborted.
                # Spec FIXME: Also look at each object if result is an array
                raise JsonLdError::ListOfLists,
                      "A list may not contain another list" if value.any? {|v| list?(v)}

                value
              when '@set'
                # If expanded property is @set, set expanded value to the result of using this algorithm recursively, passing active context, active property, and value for element.
                depth { expand(value, active_property, context, options) }
              when '@reverse'
                # If expanded property is @reverse and value is not a JSON object, an invalid @reverse value error has been detected and processing is aborted.
                raise JsonLdError::InvalidReverseValue,
                      "@reverse value must be an object: #{value.inspect}" unless value.is_a?(Hash)

                # Otherwise
                # Initialize expanded value to the result of using this algorithm recursively, passing active context, @reverse as active property, and value as element.
                value = depth { expand(value, '@reverse', context, options) }

                # If expanded value contains an @reverse member, i.e., properties that are reversed twice, execute for each of its property and item the following steps:
                if value.has_key?('@reverse')
                  debug("@reverse") {"double reverse: #{value.inspect}"}
                  value['@reverse'].each do |property, item|
                    # If result does not have a property member, create one and set its value to an empty array.
                    # Append item to the value of the property member of result.
                    (output_object[property] ||= []).concat([item].flatten.compact)
                  end
                end

                # If expanded value contains members other than @reverse:
                unless value.keys.reject {|k| k == '@reverse'}.empty?
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
              when '@explicit', '@default', '@embed', '@explicit', '@omitDefault', '@preserve', '@requireAll'
                # Framing keywords
                depth { [expand(value, expanded_property, context, options)].flatten }
              else
                # Skip unknown keyword
                next
              end

              # Unless expanded value is null, set the expanded property member of result to expanded value.
              debug("expand #{expanded_property}") { expanded_value.inspect}
              output_object[expanded_property] = expanded_value unless expanded_value.nil?
              next
            end

            expanded_value = if context.container(key) == '@language' && value.is_a?(Hash)
              # Otherwise, if key's container mapping in active context is @language and value is a JSON object then value is expanded from a language map as follows:
              
              # Set multilingual array to an empty array.
              ary = []

              # For each key-value pair language-language value in value, ordered lexicographically by language
              keys = options[:ordered] ? value.keys.sort : value.keys
              keys.each do |k|
                [value[k]].flatten.each do |item|
                  # item must be a string, otherwise an invalid language map value error has been detected and processing is aborted.
                  raise JsonLdError::InvalidLanguageMapValue,
                        "Expected #{item.inspect} to be a string" unless item.is_a?(String)

                  # Append a JSON object to expanded value that consists of two key-value pairs: (@value-item) and (@language-lowercased language).
                  ary << {
                    '@value' => item,
                    '@language' => k.downcase
                  }
                end
              end

              ary
            elsif context.container(key) == '@index' && value.is_a?(Hash)
              # Otherwise, if key's container mapping in active context is @index and value is a JSON object then value is expanded from an index map as follows:
              
              # Set ary to an empty array.
              ary = []

              # For each key-value in the object:
              keys = options[:ordered] ? value.keys.sort : value.keys
              keys.each do |k|
                # Initialize index value to the result of using this algorithm recursively, passing active context, key as active property, and index value as element.
                index_value = depth { expand([value[k]].flatten, key, context, options) }
                index_value.each do |item|
                  item['@index'] ||= k
                  ary << item
                end
              end
              ary
            else
              # Otherwise, initialize expanded value to the result of using this algorithm recursively, passing active context, key for active property, and value for element.
              depth { expand(value, key, context, options) }
            end

            # If expanded value is null, ignore key by continuing to the next key from element.
            if expanded_value.nil?
              debug(" => skip nil value")
              next
            end
            debug {" => #{expanded_value.inspect}"}

            # If the container mapping associated to key in active context is @list and expanded value is not already a list object, convert expanded value to a list object by first setting it to an array containing only expanded value if it is not already an array, and then by setting it to a JSON object containing the key-value pair @list-expanded value.
            if context.container(key) == '@list' && !list?(expanded_value)
              debug(" => ") { "convert #{expanded_value.inspect} to list"}
              expanded_value = {'@list' => [expanded_value].flatten}
            end
            debug {" => #{expanded_value.inspect}"}

            # Otherwise, if the term definition associated to key indicates that it is a reverse property
            # Spec FIXME: this is not an otherwise.
            if (td = context.term_definitions[key]) && td.reverse_property
              # If result has no @reverse member, create one and initialize its value to an empty JSON object.
              reverse_map = output_object['@reverse'] ||= {}
              [expanded_value].flatten.each do |item|
                # If item is a value object or list object, an invalid reverse property value has been detected and processing is aborted.
                raise JsonLdError::InvalidReversePropertyValue,
                      item.inspect if value?(item) || list?(item)

                # If reverse map has no expanded property member, create one and initialize its value to an empty array.
                # Append item to the value of the expanded property member of reverse map.
                merge_value(reverse_map, expanded_property, item)
              end
            else
              # Otherwise, if key is not a reverse property:
              # If result does not have an expanded property member, create one and initialize its value to an empty array.
              (output_object[expanded_property] ||= []).concat([expanded_value].flatten)
            end
          end

          debug("output object") {output_object.inspect}

          # If result contains the key @value:
          if value?(output_object)
            unless (output_object.keys - %w(@value @language @type @index)).empty? &&
                   (output_object.keys & %w(@language @type)).length < 2
              # The result must not contain any keys other than @value, @language, @type, and @index. It must not contain both the @language key and the @type key. Otherwise, an invalid value object error has been detected and processing is aborted.
              raise JsonLdError::InvalidValueObject,
              "value object has unknown keys: #{output_object.inspect}"
            end

            output_object.delete('@language') if output_object['@language'].to_s.empty?
            output_object.delete('@type') if output_object['@type'].to_s.empty?

            # If the value of result's @value key is null, then set result to null.
            return nil if output_object['@value'].nil?

            if !output_object['@value'].is_a?(String) && output_object.has_key?('@language')
              # Otherwise, if the value of result's @value member is not a string and result contains the key @language, an invalid language-tagged value error has been detected (only strings can be language-tagged) and processing is aborted.
              raise JsonLdError::InvalidLanguageTaggedValue,
                    "when @language is used, @value must be a string: #{@value.inspect}"
            elsif !output_object.fetch('@type', "").is_a?(String) ||
                  !context.expand_iri(output_object.fetch('@type', ""), vocab: true, depth: @depth).is_a?(RDF::URI)
              # Otherwise, if the result has a @type member and its value is not an IRI, an invalid typed value error has been detected and processing is aborted.
              raise JsonLdError::InvalidTypedValue,
                    "value of @type must be an IRI: #{output_object['@type'].inspect}"
            end
          elsif !output_object.fetch('@type', []).is_a?(Array)
            # Otherwise, if result contains the key @type and its associated value is not an array, set it to an array containing only the associated value.
            output_object['@type'] = [output_object['@type']]
          elsif output_object.keys.any? {|k| %w(@set @list).include?(k)}
            # Otherwise, if result contains the key @set or @list:
            # The result must contain at most one other key and that key must be @index. Otherwise, an invalid set or list object error has been detected and processing is aborted.
            raise JsonLdError::InvalidSetOrListObject,
                  "@set or @list may only contain @index: #{output_object.keys.inspect}" unless
                  (output_object.keys - %w(@set @list @index)).empty?

            # If result contains the key @set, then set result to the key's associated value.
            return output_object['@set'] if output_object.keys.include?('@set')
          end

          # If result contains only the key @language, set result to null.
          return nil if output_object.keys == %w(@language)

          # If active property is null or @graph, drop free-floating values as follows:
          if (active_property || '@graph') == '@graph' &&
            (output_object.keys.any? {|k| %w(@value @list).include?(k)} ||
             (output_object.keys - %w(@id)).empty?)
            debug(" =>") { "empty top-level: " + output_object.inspect}
            return nil
          end

          # Re-order result keys if ordering
          if options[:ordered]
            output_object.keys.kw_sort.inject({}) {|map, kk| map[kk] = output_object[kk]; map}
          else
            output_object
          end
        end
      else
        # Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
        return nil if input.nil? || active_property.nil? || active_property == '@graph'
        context.expand_value(active_property, input, depth: @depth)
      end

      debug {" => #{result.inspect}"}
      result
    end
  end
end
