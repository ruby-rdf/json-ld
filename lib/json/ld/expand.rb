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
      debug("expand") {"input: #{input.class}, property: #{property.inspect}, context: #{context.inspect}"}
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        depth do
          input.map do |v|
            raise ProcessingError::ListOfLists, "A list may not contain another list" if v.is_a?(Array)
            expand(v, property, context, options)
          end.compact
        end
      when Hash
        # Merge context
        context = context.parse(input['@context']) if input['@context']

        result = Hash.ordered
        input.each do |key, value|
          debug("expand") {"#{key}: #{value.inspect}"}
          expanded_key = context.mapping(key) || key
          
          # Skip nil values except for @context
          if value.nil? && expanded_key != '@context'
            debug("expand") {"skip nil value: #{value.inspect}"}
            next
          end
          
          # Need to look at hash values that need to be removed early
          if value.is_a?(Hash)
            if value.fetch('@value', 'default').nil?
              debug("expand") {"skip object with nil @value: #{value.inspect}"}
              next
            end
            if value.fetch('@list', 'default').nil?
              debug("expand") {"skip object with nil @list: #{value.inspect}"}
              next
            end
          end

          case expanded_key
          when '@context'
            # Ignore in output
          when '@id', '@type'
            # If the key is @id or @type and the value is a string, expand the value according to IRI Expansion.
            expanded_value = case value
            when String then context.expand_iri(value, :position => :subject, :depth => @depth).to_s
            else depth { expand(value, property, context, options) }
            end
            next if expanded_value.nil?

            # For @type, values MUST be modified to an array form, unless already in array form, unless
            # it is used along with @value to designate a datatype.
            expanded_value = [expanded_value] if expanded_key == '@type' && !expanded_value.is_a?(Array) && !input.has_key?('@value')

            result[expanded_key] = expanded_value
            debug("expand") {" => #{expanded_value.inspect}"}
          when '@value', '@language'
            raise ProcessingError::Lossy, "Value of #{expanded_key} must be a string, was #{value.inspect}" unless value.is_a?(String)
            result[expanded_key] = value
            debug("expand") {" => #{result[expanded_key].inspect}"}
          when '@list'
            # value must be an array, expand values of the array
            raise ProcessingError::ListOfLists, "A list may not contain another list" if options[:in_list]
            raise ProcessingError, "Value of @list must be an array" unless value.is_a?(Array)
            result[expanded_key] = depth { expand(value, property, context, options.merge(:in_list => true)) }
          else
            # 2.2.3) Otherwise, if the key is not a keyword, expand the key according to IRI Expansion rules and set as active property.
            expanded_key = context.expand_iri(key, :position => :predicate, :depth => @depth).to_s unless key[0,1] == '@'

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
            result[expanded_key] = value
            debug("expand") {" => #{value.inspect}"}
          end
        end
        result
      else
        # 2.3) Otherwise, unless the value is a number, expand the value according to the Value Expansion rules, passing active property.
        context.expand_value(property, input, :position => :object, :depth => @depth) unless input.nil?
      end
    end
  end
end