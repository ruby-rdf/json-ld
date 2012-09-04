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
          input.each do |key, value|
            # Remove property from element expand property according to the steps outlined in IRI Expansion
            property = context.expand_iri(key, :position => :predicate, :quiet => true)

            # Set active property to the original un-expanded property if property if not a keyword
            active_property = key unless key[0,1] == '@'
            debug("expand property") {"#{active_property.inspect}, expanded: #{property}, value: #{value.inspect}"}
          
            # If property does not expand to a keyword or absolute IRI, remove property from element
            # and continue to the next property from element
            if property.nil?
              debug(" => ") {"skip nil key"}
              next
            end
            property = property.to_s

            expanded_value = case property
            when '@id'
              # If the property is @id the value must be a string. Expand the value according to IRI Expansion.
              context.expand_iri(value, :position => :subject, :quiet => true).to_s
            when '@type'
              # Otherwise, if the property is @type the value must be a string, an array of strings
              # or an empty JSON Object.
              # Expand value or each of it's entries according to IRI Expansion
              debug("@type") {"value: #{value.inspect}"}
              case value
              when Array
                depth do
                  [value].flatten.map do |v|
                    v = v['@id'] if node_reference?(v)
                    raise ProcessingError, "Object value must be a string or a node reference: #{v.inspect}" unless v.is_a?(String)
                    context.expand_iri(v, options.merge(:position => :property, :quiet => true)).to_s
                  end
                end
              when Hash
                # Empty object used for @type wildcard or node reference
                if node_reference?(value)
                  context.expand_iri(value['@id'], options.merge(:position => :property, :quiet => true)).to_s
                elsif !value.empty?
                  raise ProcessingError, "Object value of @type must be empty or a node reference: #{value.inspect}"
                else
                  value
                end
              else
                context.expand_iri(value, options.merge(:position => :property, :quiet => true)).to_s
              end
            when '@value', '@language'
              # Otherwise, if the property is @value or @language the value must not be a JSON object or an array.
              raise ProcessingError::Lossy, "Value of #{property} must be a string, was #{value.inspect}" if value.is_a?(Hash) || value.is_a?(Array)
              value
            when '@list', '@set', '@graph'
              # Otherwise, if the property is @list, @set, or @graph, expand value recursively
              # using this algorithm, passing copies of the active context and active property.
              # If the expanded value is not an array, convert it to an array.
              value = [value] unless value.is_a?(Array)
              value = depth { expand(value, active_property, context, options) }

              # If property is @list, and any expanded value
              # is an object containing an @list property, throw an exception, as lists of lists are not supported
              if property == '@list' && value.any? {|v| v.is_a?(Hash) && v.has_key?('@list')}
                raise ProcessingError::ListOfLists, "A list may not contain another list"
              end

              value
            else
              # Otherwise, expand value recursively using this algorithm, passing copies of the active context and active property.
              depth { expand(value, active_property, context, options) }
            end

            # moved from step 2.2.3
            # If expanded value is null and property is not @value, continue with the next property
            # from element.
            if property != '@value' && expanded_value.nil?
              debug(" => skip nil value")
              next
            end

            # If the expanded value is not null and property is not a keyword
            # and the active property has a @container set to @list,
            # convert value to an object with an @list property whose value is set to value
            # (unless value is already in that form)
            if expanded_value && property[0,1] != '@' && context.container(active_property) == '@list' &&
               (!expanded_value.is_a?(Hash) || !expanded_value.fetch('@list', false))
               debug(" => ") { "convert #{expanded_value.inspect} to list"}
              expanded_value = {'@list' => [expanded_value].flatten}
            end

            # Convert value to array form unless value is null or property is @id, @type, @value, or @language.
            if !%(@id @language @type @value).include?(property) && !expanded_value.is_a?(Array)
              debug(" => make #{expanded_value.inspect} an array")
              expanded_value = [expanded_value]
            end

            if output_object.has_key?(property)
              # If element already contains a property property, append value to the existing value.
              output_object[property] += expanded_value
            else
              # Otherwise, create a property property with value as value.
              output_object[property] = expanded_value
            end
            debug {" => #{expanded_value.inspect}"}
          end

          debug("output object") {output_object.inspect}

          # If the processed element has an @value property
          if output_object.has_key?('@value')
            output_object.delete('@language') if output_object['@language'].to_s.empty?
            output_object.delete('@type') if output_object['@type'].to_s.empty?
            if output_object.keys.length > 2 || (%w(@language @type) - output_object.keys).empty?
              raise ProcessingError, "element must not have more than one other property, which can either be @language or @type with a string value." unless value.is_a?(String)
            end

            # if the value of @value equals null, replace element with the value of null.
            return nil if output_object['@value'].nil?
          elsif !output_object.fetch('@type', []).is_a?(Array)
            # Otherwise, if element has an @type property and it's value is not in the form of an array,
            # convert it to an array.
            output_object['@type'] = [output_object['@type']]
          end

          # If element has an @set or @list property, it must be the only property. Set element to the value of @set;
          # leave @list untouched.
          if !(%w(@set @list) & output_object.keys).empty?
            raise ProcessingError, "element must have only @set, @list or @graph" if output_object.keys.length > 1
            
            output_object = output_object.values.first unless output_object.has_key?('@list')
          end

          # If element has just a @language property, set element to null.
          output_object unless output_object.is_a?(Hash) && output_object.keys == %w(@language)
        end
      else
        # Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
        context.expand_value(active_property, input, :position => :object, :depth => @depth) unless input.nil?
      end

      debug {" => #{result.inspect}"}
      result
    end
  end
end