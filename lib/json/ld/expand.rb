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
    # @param [RDF::URI] predicate
    # @param [EvaluationContext] context
    # @param [Hash{Symbol => Object}] options
    # @return [Array, Hash]
    def expand(input, predicate, context, options = {})
      debug("expand") {"input: #{input.class}, predicate: #{predicate.inspect}, context: #{context.inspect}"}
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        depth do
          input.map do |v|
            raise ProcessingError::ListOfLists, "A list may not contain another list" if v.is_a?(Array)
            expand(v, predicate, context, options)
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
            else depth { expand(value, predicate, context, options) }
            end
            next if expanded_value.nil?
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
            result[expanded_key] = depth { expand(value, predicate, context, options.merge(:in_list => true)) }
          else
            # 2.2.3) Otherwise, if the key is not a keyword, expand the key according to IRI Expansion rules and set as active property.
            unless key[0,1] == '@'
              predicate = context.expand_iri(key, :position => :predicate, :depth => @depth)
              expanded_key = predicate.to_s
            end

            # 2.2.4) If the value is an array, and active property is subject to @list expansion,
            #   replace the value with a new key-value key where the key is @list and value set to the current value.
            value = {"@list" => value} if value.is_a?(Array) && context.container(predicate) == '@list'

            value = case value
            # 2.2.5) If the value is an array, process each item in the array recursively using this algorithm,
            #   passing copies of the active context and active property
            # 2.2.6) If the value is an object, process the object recursively using this algorithm,
            #   passing copies of the active context and active property.
            when Array, Hash then depth {expand(value, predicate, context, options)}
            else
              # 2.2.7) Otherwise, expand the value according to the Value Expansion rules, passing active property.
              context.expand_value(predicate, value, :position => :object, :depth => @depth)
            end
            result[expanded_key] = value
            debug("expand") {" => #{value.inspect}"}
          end
        end
        result
      else
        # 2.3) Otherwise, expand the value according to the Value Expansion rules, passing active property.
        context.expand_value(predicate, input, :position => :object, :depth => @depth) unless input.nil?
      end
    end
  end
end