require 'json/ld/utils'

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
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        depth do
          value = input.map do |v|
            raise ProcessingError::ListOfLists, "A list may not contain another list" if v.is_a?(Array)
            expand(v, property, context, options)
          end.compact
          
          # If the array is empty, return a null value, otherwise return the expanded array
          #value unless value.empty?
        end
      when Hash
        # 2.1) Update the active context according to the steps outlined in the context section
        #      and remove it from the expanded result.
        context = context.parse(input['@context']) if input['@context']

        result = Hash.ordered
        # 2.2) For each key and value in value:
        input.each do |key, value|
          debug("expand") {"#{key}: #{value.inspect}"}
          expanded_key = context.expand_iri(key, :position => :predicate, :quiet => true)
          
          # 2.2.x) If key does not expand to a keyword or absolute IRI, skip this key/value pair and remove from value
          if expanded_key.nil?
            debug {"skip nil key"}
            next
          end
          expanded_key = expanded_key.to_s

          # 2.2.1) If value is null, skip this key/value pair and remove key from value
          if value.nil? && expanded_key != '@context'
            debug {"skip nil value: #{value.inspect}"}
            next
          end
          
          # 2.2.3) Otherwise, if value is a JSON object having either a @value, @list, or @set key with a null value,
          #       skip this key/value pair.
          # FIXME: coult value be nil only after expansion?
          if value.is_a?(Hash)
            expanded_keys = value.keys {|k| context.expand_iri(k, :position => :predicate, :quiet => true)}
            k = (%w(@list @set @value) & expanded_keys).first

            if k && value.values.first.nil?
              debug {"skip object with nil #{k}: #{value.inspect}"}
              next
            end

            # 2.2.4) Otherwise, if value is a JSON object having a @set key with a non-null value,
            #        replace value with the value of @set.
            if expanded_keys.include?('@set')
              debug {"=> #{value['@set'].inspect}"}
              value = value['@set']
            end
          end

          case expanded_key
          when '@context'
            # Ignore in output
          when '@id', '@type'
            # If the key is @id or @type and the value is a string, expand the value according to IRI Expansion.
            position = if expanded_key == '@type' && input.keys.detect {|k| context.expand_iri(k) == '@value'}
              :datatype
            else
              :subject
            end
            expanded_value = case value
            when String
              v = context.expand_iri(value, :position => position, :debug => @debug)
              v.to_s unless v.nil?
            else depth { expand(value, property, context, options) }
            end
            debug {"=> #{expanded_value.inspect}"}
            # If value expands to null and object contains only the @id key, abort processing this object
            # and return null
            if expanded_value.nil?
              if expanded_key == '@id' && input.keys == ['@id']
                debug("expand") {"return because of nil @id"}
                return nil
              end

              debug("expand") {"skip nil #{value.inspect}"}
              next
            end

            debug("expand(#{expanded_key})") { "flatten or make array #{expanded_value.inspect}"}
            # For @id, a single value MUST NOT be represented in array form
            expanded_value = expanded_value.first if expanded_key == '@id' &&  expanded_value.is_a?(Array) && expanded_value.length == 1

            # For @type, values MUST be modified to an array form, unless already in array form, unless
            # it is used along with @value to designate a datatype.
            expanded_value = [expanded_value] if expanded_key == '@type' && !expanded_value.is_a?(Array) && !input.has_key?('@value')

            result[expanded_key] = expanded_value
            debug {" => #{expanded_value.inspect}"}
          when '@value', '@language'
            raise ProcessingError::Lossy, "Value of #{expanded_key} must be a string, was #{value.inspect}" unless value.is_a?(String)
            result[expanded_key] = value
            debug {" => #{result[expanded_key].inspect}"}
          when '@list'
            # value must be an array, expand values of the array
            raise ProcessingError::ListOfLists, "A list may not contain another list" if options[:in_list]
            raise ProcessingError, "Value of @list must be an array" unless value.is_a?(Array)
            result[expanded_key] = depth { expand(value, property, context, options.merge(:in_list => true)) } || []
          when '@graph'
            # value must be an array, expand values of the array
            raise ProcessingError, "Value of @graph must be an array" unless value.is_a?(Array)
            result = depth { expand(value, property, context, options) } || []
            debug {" => #{result.inspect}"}
            return result
          else
            # 2.2.4) If the value is an array, and active property is subject to @list expansion,
            #   replace the value with a new key-value key where the key is @list and value set to the current value.
            value = {"@list" => value} if value.is_a?(Array) && context.container(key) == '@list'

            # 2.3.x) If value is not an array, replace value with a new array containing the existing
            #   value.
            value = [value] unless value.is_a?(Array)
            
            # 2.3.x) process each item in the array recursively using this algorithm,
            #   passing copies of the active context and active property
            value = depth {expand(value, key, context, options)}

            # 2.2.x) If output object already contains a key for active property, add the expanded value to
            #  the existing value,
            #  Otherwise, add active property to output object with expanded value which MUST be in array form.
            result[expanded_key] = value unless value.nil?
            debug {" => #{value.inspect}"}
          end
        end
        debug {" => #{result.inspect}"}
        result
      else
        # 2.3) Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
        context.expand_value(property, input, :position => :object, :depth => @depth) unless input.nil?
      end
    end
  end
end