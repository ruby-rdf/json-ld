module JSON::LD
  ##
  # Expand module, used as part of API
  module Expand
    include Utils

    ##
    # Expand an Array or Object given an active context and performing local context expansion.
    #
    # @param [Array, Hash] input
    # @param [String] property
    # @param [EvaluationContext] context
    # @param [Hash{Symbol => Object}] options
    # @return [Array, Hash]
    def expand(input, property, context, options = {})
      debug("expand") {"input: #{input.inspect}, property: #{property.inspect}, context: #{context.inspect}"}
      result = case input
      when Array
        # 1) If element is an array, process each item in element recursively using this algorithm,
        #    passing copies of the active context and active property and removing null entries.
        #   If any result is a JSON Object with a property of @set (or alias thereof), remove that object,
        #   and append the array value to element.
        depth do
          input.map do |v|
            expand(v, property, context, options)
          end.map do |v|
            # Flatten included @set
            if v.is_a?(Hash) && v.has_key?('@set')
              debug("expand") {"flatten #{v} in array context"}
              v['@set']
            else
              v
            end
          end.flatten.compact
        end
      when Hash
        # 2) Otherwise, if element is an object
        # 2.1) If element has a @context property, update the active context according to the steps outlined
        #   in Context Processing and remove the @context property.
        if input.has_key?('@context')
          context = context.parse(input.delete('@context'))
          debug("expand") {"evaluation context: #{context.inspect}"}
        end

        depth do
          output_object = Hash.ordered
          # 2.2) For each property and value in element:
          input.each do |key, value|
            # 2.2.1) Set property as active property and the result of performing IRI Expansion on property as
            #   expanded property.
            expanded_key = context.expand_iri(key, :position => :predicate, :quiet => true)
            debug("expand key") {"#{key}, expanded: #{expanded_key}, value: #{value.inspect}"}
          
            # 2.2.2) If property does not expand to a keyword or absolute IRI, remove property from element
            #   and continue to the next property from element
            if expanded_key.nil?
              debug {"skip nil key"}
              next
            end
            expanded_key = expanded_key.to_s

            # 2.2.3) If expanded property is @value and value is null, skip further processing and return null as the expanded version of element
            if expanded_key == '@value' && value.nil?
              debug {"skip nil @value: #{value.inspect}"}
              return nil
            end

            # 2.2.4) If value is null, skip this key/value pair and remove key from value
            if value.nil? && expanded_key != '@context'
              debug {"skip nil value: #{value.inspect}"}
              next
            end

            # 2.2.5) Otherwise, if value is a JSON object having either a @value, @list, or @set key with a null value,
            #       skip this key/value pair.
            # FIXME: could value be nil only after expansion?
            if value.is_a?(Hash)
              expanded_keys = value.keys.map {|k| context.expand_iri(k, :position => :predicate, :quiet => true).to_s}
              debug("expand") {"expanded keys: #{expanded_keys.inspect}"}
              k = (%w(@list @set @value) & expanded_keys).first

              if k && value.values.first.nil?
                debug {"skip object with nil #{k}: #{value.inspect}"}
                next
              end

              # 2.2.6) If value is a JSON object having a @set property (or an alias thereof) with a non-null
              #   value, replace value with the value of @set.
              if expanded_keys.include?('@set')
                debug {"=> #{value['@set'].inspect}"}
                value = value['@set']
              end

              # 2.2.7) Otherwise, if value is a JSON object having a @list key, that value MUST
              #   be an array. Process each entry in that array recursively using this algorithm
              #   passing copies of the active context and active property removing all items that equal to null.
              #   Add an entry in the output object for expanded property with value and continue to the
              #   next entry in element.
              if expanded_keys.include?('@list')
                debug("expand") { "short cut value with @list: #{value.inspect}"}
                list_array = value.values.first
                raise ProcessingError, "Value of @list must be an array, was #list_array.inspect}" unless list_array.is_a?(Array)
                list_array = depth { expand(list_array, property, context, options.merge(:in_list => true)) }
                output_object[expanded_key] = {"@list" => list_array}
                debug {" => #{output_object[expanded_key].inspect}"}
                next
              end
            end

            case expanded_key
            when '@id', '@type'
              # A new object starts a new context for defining lists
              options = options.merge(:in_list => false) if options[:in_list]

              # 2.2.8) If the property is @id and the value is a string, expand the value according to IRI Expansion.
              # 2.2.9) Otherwise, if the property is @type and the value is a string expand value according to IRI Expansion.
              position = if expanded_key == '@type' && input.keys.detect {|k| context.expand_iri(k, :quiet => true) == '@value'}
                :datatype
              else
                :subject
              end
              expanded_value = case value
              when String
                v = context.expand_iri(value, :position => position, :quiet => true)
                v.to_s unless v.nil?
              when Array
                # Otherwise, if the expanded property is @type and the value is an array, expand every entry according to IRI Expansion.
                depth { value.map {|v| context.expand_iri(v, options.merge(:position => :property, :quiet => true)).to_s} }
              else
                # FIXME: document?
                # Otherwise, expand as a value
                depth { expand(value, property, context, options) }
              end
              debug {"=> #{expanded_value.inspect}"}
              if expanded_value.nil?
                debug("expand") {"skip nil #{value.inspect}"}
                next
              end

              debug("expand(#{expanded_key})") { "flatten or make array #{expanded_value.inspect}"}
              # For @id, a single value MUST NOT be represented in array form
              expanded_value = expanded_value.first if expanded_key == '@id' &&  expanded_value.is_a?(Array) && expanded_value.length == 1

              # For @type, values MUST be modified to an array form, unless already in array form, unless
              # it is used along with @value to designate a datatype.
              expanded_value = [expanded_value] if expanded_key == '@type' && !expanded_value.is_a?(Array) && !input.has_key?('@value')

              output_object[expanded_key] = expanded_value
              debug {" => #{expanded_value.inspect}"}
            when '@value', '@language'
              # 2.2.10) Otherwise, if the expanded property is @value or @language, the value is not subject to further expansion.
              raise ProcessingError::Lossy, "Value of #{expanded_key} must be a string, was #{value.inspect}" unless value.is_a?(String)
              output_object[expanded_key] = value
              debug {" => #{output_object[expanded_key].inspect}"}
            when '@list'
              raise ProcessingError::ListOfLists, "A list may not contain another list"
            when '@graph'
              # Otherwise, if the expanded property is @graph, replace the entire object with the result of
              #   performing this algorithm on the members of the value and terminate further processing of this object
              raise ProcessingError, "Value of @graph must be an array" unless value.is_a?(Array)
              output_object = depth { expand(value, property, context, options) } || []
            else
              # 2.2.12) process value as follows:
              if value.is_a?(Array)
                # 2.2.12.1) If the value is an array, and active property is subject to @list expansion,
                #   replace the value with a new object where the key is @list and value set to the current value
                #   updated by recursively using this algorithm.
                if context.container(key) == '@list'
                  raise ProcessingError::ListOfLists, "A list may not contain another list" if options[:in_list]
                  value = depth {expand(value, key, context, options.merge(:in_list => true))}
                  value = {"@list" => value}
                end
              else
                # 2.2.12.2) Otherwise, if value is not an array, replace value with an array containing value
                value = [value]
              end
            
              # 2.2.12.3) process each item in the array recursively using this algorithm,
              #   passing copies of the active context and active property
              value = depth {expand(value, key, context, options)} if value.is_a?(Array)

              if output_object.has_key?(expanded_key)
                # 2.2.13) If output object already contains an entry for expanded property, add the expanded value to
                #  the existing value,
                output_object[expanded_key] += value
              else
                #  2.2.14) Otherwise, add expanded property to output object with expanded value.
                output_object[expanded_key] = value
              end
              debug {" => #{value.inspect}"}
            end
          end
          output_object
        end
      else
        # 2.3) Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
        context.expand_value(property, input, :position => :object, :depth => @depth) unless input.nil?
      end

      debug {" => #{result.inspect}"}
      result
    end
  end
end