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
        case result.length
        when 0
          nil
        when 1
          result.first
        else
          result
        end
      when Hash
        # Otherwise, if value is an object
        result = Hash.ordered
        
        if k = %w(@list @set @value).detect {|container| input.has_key?(container)}
          debug("compact") {"#{k}: container(#{property}) = #{context.container(property)}"}
        end

        k ||= '@id' if input.keys == ['@id']
        
        case k
        when '@value', '@id'
          # If the value only an @id key or the value contains a @value key, the compacted value is
          # the result of performing Value Compaction on the value.
          v = context.compact_value(property, input, :depth => @depth)
          debug("compact") {"value optimization, return as #{v.inspect}"}
          return v
        when '@list', '@set'
          # Otherwise, if the value contains only a @list or @set key, compact the array value
          # by performing this algorithm, ensuring that the result remains an array.
          compacted_key = context.compact_iri(k, :position => :predicate, :depth => @depth)
          v = depth { compact(input[k], "") }
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
          compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)
          debug {" => compacted key: #{compacted_key.inspect}"} unless compacted_key == key

          result[compacted_key] = if %(@id @type).include?(key) && value.is_a?(String)
            debug {" => compacted string for #{key}"}
            context.compact_iri(value, :position => :subject, :depth => @depth)
          elsif %(@id @type).include?(key) && value.is_a?(Hash) && value.keys == ['@id']
            debug {" => compacted string for #{key} with {@id}"}
            context.compact_iri(value['@id'], :position => :subject, :depth => @depth)
          else
            # Otherwise, the value MUST be an array, the compacted value is the result of performing
            # this algorithm on the value.
            compacted_value = depth {compact(value, compacted_key)}
            debug {" => compacted value: #{compacted_value.inspect}"}
            compacted_value
          end
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
