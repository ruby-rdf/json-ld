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
    # @param [EvaluationContext] context
    # @param [Hash{Symbol => Object}] options
    # @return [Array, Hash]
    def expand(input, active_property, context, options = {})
      debug("expand") {"input: #{input.inspect}, active_property: #{active_property.inspect}, context: #{context.inspect}"}
      result = case input
      when Array
        # If element is an array, process each item in element recursively using this algorithm,
        # passing copies of the active context and active property. If the expanded entry is null, drop it.
        depth do
          is_list = context.container(active_property) == '@list'
          value = input.map do |v|
            # If active property has a @container set to @list, and item is an array,
            # or the result of expanding any item is an object containing an @list property,
            # throw an exception as lists of lists are not allowed.
            raise ProcessingError::ListOfLists, "A list may not contain another list" if v.is_a?(Array) && is_list

            expand(v, active_property, context, options)
          end.flatten.compact

          if is_list && value.any? {|v| v.is_a?(Hash) && v.has_key?('@list')}
            raise ProcessingError::ListOfLists, "A list may not contain another list"
          end

          value
        end
      when Hash
        # Otherwise, if element is an object
        # If element has a @context property, update the active context according to the steps outlined
        # in Context Processing and remove the @context property.
        if input.has_key?('@context')
          context = context.parse(input.delete('@context'))
          debug("expand") {"evaluation context: #{context.inspect}"}
        end

        depth do
          output_object = Hash.ordered
          # Then, proceed and process each property and value in element as follows:
          input.keys.kw_sort.each do |property|
            value = input[property]
            expanded_property = context.expand_iri(property, :position => :predicate, :quiet => true, :namer => namer)

            if expanded_property.is_a?(Array)
              # If expanded property is an array, remove every element which is not a absolute IRI.
              expanded_property = expanded_property.map {|p| p.to_s if p && p.uri? && p.absolute? || p.node?}.compact
              expanded_property = nil if expanded_property.empty?
            elsif expanded_property.is_a?(RDF::Resource)
              expanded_property = expanded_property.to_s
            end

            debug("expand property") {"ap: #{active_property.inspect}, expanded: #{expanded_property.inspect}, value: #{value.inspect}"}

            # If expanded property is an empty array, or null, continue with the next property from element
            if expanded_property.nil?
              debug(" => ") {"skip nil property"}
              next
            end
            expanded_property

            if expanded_property.is_a?(String) && expanded_property[0,1] == '@'
              expanded_value = case expanded_property
              when '@id'
                # If expanded property is @id, value must be a string. Set the @id member in result to the result of expanding value according the IRI Expansion algorithm relative to the document base and re-labeling Blank Nodes.
                context.expand_iri(value, :position => :subject, :quiet => true, :namer => namer).to_s
              when '@type'
                # If expanded property is @type, value must be a string or array of strings. Set the @type member of result to the result of expanding value according the IRI Expansion algorithm relative to the document base and re-labeling Blank Nodes, unless that result is an empty array.
                debug("@type") {"value: #{value.inspect}"}
                case value
                when Array
                  depth do
                    [value].flatten.map do |v|
                      v = v['@id'] if node_reference?(v)
                      raise ProcessingError, "Object value must be a string or a node reference: #{v.inspect}" unless v.is_a?(String)
                      context.expand_iri(v, options.merge(:position => :subject, :quiet => true, :namer => namer)).to_s
                    end
                  end
                when Hash
                  # Empty object used for @type wildcard or node reference
                  if node_reference?(value)
                    context.expand_iri(value['@id'], options.merge(:position => :property, :quiet => true, :namer => namer)).to_s
                  elsif !value.empty?
                    raise ProcessingError, "Object value of @type must be empty or a node reference: #{value.inspect}"
                  else
                    value
                  end
                else
                  context.expand_iri(value, options.merge(:position => :property, :quiet => true, :namer => namer)).to_s
                end
              when '@value'
                # If expanded property is @value, value must be a scalar or null. Set the @value member of result to value.
                raise ProcessingError::Lossy, "Value of #{expanded_property} must be a string, was #{value.inspect}" if value.is_a?(Hash) || value.is_a?(Array)
                value
              when '@language'
                # If expanded property is @language, value must be a string with the lexical form described in [BCP47] or null. Set the @language member of result to the lowercased value.
                raise ProcessingError::Lossy, "Value of #{expanded_property} must be a string, was #{value.inspect}" if value.is_a?(Hash) || value.is_a?(Array)
                value.to_s.downcase
              when '@annotation'
                # If expanded property is @annotation value must be a string. Set the @annotation member of result to value.
                value = value.first if value.is_a?(Array) && value.length == 1
                raise ProcessingError, "Value of @annotation is not a string: #{value.inspect}" unless value.is_a?(String)
                value.to_s
              when '@list', '@set', '@graph'
                # If expanded property is @set, @list, or @graph, set the expanded property member of result to the result of expanding value by recursively using this algorithm, along with the active context and active property. If expanded property is @list and active property is null or @graph, pass @list as active property instead.
                value = [value] unless value.is_a?(Array)
                ap = expanded_property == '@list' && ((active_property || '@graph') == '@graph') ? '@list' : active_property
                value = depth { expand(value, ap, context, options) }

                # If expanded property is @list, and any expanded value
                # is an object containing an @list property, throw an exception, as lists of lists are not supported
                if expanded_property == '@list' && value.any? {|v| v.is_a?(Hash) && v.has_key?('@list')}
                  raise ProcessingError::ListOfLists, "A list may not contain another list"
                end

                value
              else
                # Skip unknown keyword
                next
              end

              debug("expand #{expanded_property}") { expanded_value.inspect}
              output_object[expanded_property] = expanded_value
              next
            end

            expanded_value = if context.container(property) == '@language' && value.is_a?(Hash)
              # Otherwise, if value is a JSON object and property is not a keyword and its associated term entry in the active context has a @container key associated with a value of @language, process the associated value as a language map:
              
              # Set multilingual array to an empty array.
              language_map_values = []

              # For each key-value in the language map:
              value.keys.sort.each do |k|
                [value[k]].flatten.each do |v|
                  # Create a new JSON Object, referred to as an expanded language object.
                  expanded_language_object = Hash.new

                  # Add a key-value pair to the expanded language object where the key is @value and the value is the value associated with the key in the language map.
                  raise ProcessingError::LanguageMap, "Expected #{vv.inspect} to be a string" unless v.is_a?(String)
                  expanded_language_object['@value'] = v

                  # Add a key-value pair to the expanded language object where the key is @language, and the value is the key in the language map, transformed to lowercase.
                  # FIXME: check for BCP47 conformance
                  expanded_language_object['@language'] = k.downcase
                  # Append the expanded language object to the multilingual array.
                  language_map_values << expanded_language_object
                end
              end
              # Set the value associated with property to the multilingual array.
              language_map_values
            elsif context.container(property) == '@annotation' && value.is_a?(Hash)
              # Otherwise, if value is a JSON object and property is not a keyword and its associated term entry in the active context has a @container key associated with a value of @annotation, process the associated value as a annotation:
              
              # Set ary to an empty array.
              annotation_map_values = []

              # For each key-value in the object:
              value.keys.sort.each do |k|
                [value[k]].flatten.each do |v|
                  # Expand the value, adding an '@annotation' key with value equal to the key
                  expanded_value = depth { expand(v, property, context, options) }
                  next unless expanded_value
                  expanded_value['@annotation'] ||= k
                  annotation_map_values << expanded_value
                end
              end
              # Set the value associated with property to the multilingual array.
              annotation_map_values
            else
              # Otherwise, expand value by recursively using this algorithm, passing copies of the active context and property as active property.
              depth { expand(value, property, context, options) }
            end

            # Continue to the next property-value pair from element if value is null.
            if expanded_value.nil?
              debug(" => skip nil value")
              next
            end

            # If property's container mapping is set to @list and value is not a JSON object or is a JSON object without a @list member, replace value with a JSON object having a @list member whose value is set to value, ensuring that value is an array.
            if context.container(property) == '@list' &&
              (!expanded_value.is_a?(Hash) || !expanded_value.fetch('@list', false))

              debug(" => ") { "convert #{expanded_value.inspect} to list"}
              expanded_value = {'@list' => [expanded_value].flatten}
            end

            # Convert value to array form
            debug(" => ") {"expanded property: #{expanded_property.inspect}"}
            expanded_value = [expanded_value] unless expanded_value.is_a?(Array)

            if expanded_property.is_a?(Array)
              label_blanknodes(expanded_value)
              expanded_property.map(&:to_s).each do |prop|
                # label all blank nodes in value with blank node identifiers by using the Label Blank Nodes Algorithm.
                output_object[prop] ||= []
                output_object[prop] += expanded_value.dup
              end
            else
              if output_object.has_key?(expanded_property)
                # If element already contains a expanded_property property, append value to the existing value.
                output_object[expanded_property] += expanded_value
              else
                # Otherwise, create a property property with value as value.
                output_object[expanded_property] = expanded_value
              end
            end
            debug {" => #{expanded_value.inspect}"}
          end

          debug("output object") {output_object.inspect}

          # If the active property is null or @graph and element has a @value member without an @annotation member, or element consists of only an @id member, set element to null.
          debug("output object(ap)") {((active_property || '@graph') == '@graph').inspect}
          if (active_property || '@graph') == '@graph' &&
             ((output_object.has_key?('@value') && !output_object.has_key?('@annotation')) ||
              (output_object.keys - %w(@id)).empty?)
            debug("empty top-level") {output_object.inspect}
            return nil
          end

          # If the processed element has an @value property
          if output_object.has_key?('@value')
            output_object.delete('@language') if output_object['@language'].to_s.empty?
            output_object.delete('@type') if output_object['@type'].to_s.empty?
            if (%w(@annotation @language @type) - output_object.keys).empty?
              raise ProcessingError, "element must not have more than one other property other than @annotation, which can either be @language or @type with a string value." unless value.is_a?(String)
            end

            # if the value of @value equals null, replace element with the value of null.
            return nil if output_object['@value'].nil?
          elsif !output_object.fetch('@type', []).is_a?(Array)
            # Otherwise, if element has an @type property and it's value is not in the form of an array,
            # convert it to an array.
            output_object['@type'] = [output_object['@type']]
          end

          # If element has an @set or @list property, it must be the only property (other tha @annotation). Set element to the value of @set;
          # leave @list untouched.
          if !(%w(@set @list) & output_object.keys).empty?
            o_keys = output_object.keys - %w(@set @list @annotation)
            raise ProcessingError, "element must have only @set or  @list: #{output_object.keys.inspect}" if o_keys.length > 1
            
            output_object = output_object.values.first unless output_object.has_key?('@list')
          end

          # Re-order result keys
          if output_object.is_a?(Hash) && output_object.keys == %w(@language)
            # If element has just a @language property, set element to null.
            nil
          elsif output_object.is_a?(Hash)
            r = Hash.ordered
            output_object.keys.kw_sort.each {|k| r[k] = output_object[k]}
            r
          else
            output_object
          end
        end
      else
        # Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
        context.expand_value(active_property, input,
          :position => :subject, :namer => namer, :depth => @depth
        ) unless input.nil? || active_property.nil? || active_property == '@graph'
      end

      debug {" => #{result.inspect}"}
      result
    end

    protected
    # @param [Array, Hash] input
    def label_blanknodes(element)
      if element.is_a?(Array)
        element.each {|e| label_blanknodes(e)}
      elsif list?(element)
        element['@list'].each {|e| label_blanknodes(e)}
      elsif element.is_a?(Hash)
        element.keys.sort.each do |k|
          label_blanknodes(element[k])
        end
        if node?(element) and !element.has_key?('@id')
          element['@id'] = namer.get_name(nil)
        end
      end
    end
  end
end
