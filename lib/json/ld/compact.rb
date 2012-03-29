require 'json/ld/utils'

module JSON::LD
  module Compact
    include Utils

    ##
    # Compact an expanded Array or Hash given an active property and a context.
    #
    # @param [Array, Hash] input
    # @param [String] property (nil)
    # @param [EvaluationContext] context
    # @return [Array, Hash]
    def compact(input, property = nil)
      if property.nil?
        debug("compact") {"input: #{input.inspect}, ec: #{context.inspect}"}
      else
        debug("compact") {"property: #{property.inspect}"}
      end
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        debug("compact") {"Array[#{input.length}]"}
        result = depth {input.map {|v| compact(v, property)}}
        # FIXME: account for @set
        result.length == 1 ? result.first : result
      when Hash
        # Otherwise, if value is an object
        result = Hash.ordered
        
        if k = %w(@list @set @value).detect {|container| input.has_key?(container)}
          debug("compact") {"#{k}: container(#{property}) = #{context.container(property)}"}
        end

        k ||= '@id' if input.keys == ['@id']
        
        case k
        when '@value', '@id'
          # If the value only has an @id key or the value contains a @value key, the compacted value is
          # the result of performing Value Compaction on the value.
          v = context.compact_value(property, input, :depth => @depth)
          debug("compact") {"value optimization, return as #{v.inspect}"}
          return v
        when '@list'
          # Otherwise, if the value contains only a @list key, compact the array value
          # by performing this algorithm, ensuring that the result remains an array.
          # FIXME: should use active property, but if there are more than one mapping
          #   for the property with different coercions, how to pick best?
          #   For example:
          #     * list/set coercion with xsd:integer
          #     * list/set coercion with @id
          compacted_key = context.compact_iri(k, :position => :predicate, :depth => @depth)
          v = depth { compact(input[k], property) }
          v = [v].compact unless v.is_a?(Array)
          
          # If the active property is subject to list or set coercion the compacted value
          # is the compacted array value.
          # Otherwise, the value is a new object, using any compacted representation of
          # @list or @set as the key and the compacted array value
          v = {compacted_key => v} unless context.container(property) == k
          debug("compact") {"value optimization, return as #{v.inspect}"}
          return v
        end

        input.each do |key, value|
          debug("compact") {"#{key}: #{value.inspect}"}
          
          # FIXME: right now, this just chooses any key representation, it probably
          #   should look recursively to find the best key representation based
          #   on the values. Note that this might mean splitting multiple values into
          #   separate keys.
          compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)
          debug {" => compacted key: #{compacted_key.inspect}"} unless compacted_key == key

          rval = if %(@id @type).include?(key) && value.is_a?(String)
            debug {" => compacted string for #{key}"}
            context.compact_iri(value, :position => :subject, :depth => @depth)
          elsif %(@id @type).include?(key) && value.is_a?(Hash) && value.keys == ['@id']
            debug {" => compacted string for #{key} with {@id}"}
            context.compact_iri(value['@id'], :position => :subject, :depth => @depth)
          elsif key == '@type' && value.is_a?(Array)
            # Otherwise, if key is @type and value is an array, perform value compaction
            # on all members of the array
            compacted_value = value.map do |v|
              if v.is_a?(String)
                context.compact_iri(v, :position => :subject, :depth => @depth)
              else
                context.compact_value(key, v, :depth => @depth)
              end
            end
            debug {" => compacted value(@type): #{compacted_value.inspect}"}
            compacted_value = compacted_value.first if compacted_value.length == 1
            compacted_value
          else
            # Otherwise, the value MUST be an array, the compacted value is the result of performing
            # this algorithm on the value.
            compacted_value = depth {self.compact(value, compacted_key)}
            debug {" => compacted value: #{compacted_value.inspect}"}
            
            # If compacted key is subject to @set coercion, ensure that compacted value is expressed
            # as an array
            if !compacted_value.is_a?(Array) && context.container(compacted_key) == '@set'
              compacted_value = [compacted_value].compact
              debug {" => as @set: #{compacted_value.inspect}"}
            end
            compacted_value
          end
          
          result[compacted_key] = rval unless rval.nil?
        end
        result
      else
        # For other types, the compacted value is the input value
        debug("compact") {input.class.to_s}
        input
      end
    end
  end
end
