require 'json/ld/utils'

module JSON::LD
  module Compact
    include Utils

    ##
    # Compact an expanded Array or Hash given an active property and a context.
    #
    # @param [Array, Hash] input
    # @param [RDF::URI] predicate (nil)
    # @param [EvaluationContext] context
    # @return [Array, Hash]
    def compact(input, predicate = nil)
      debug("compact") {"input: #{input.class}, predicate: #{predicate.inspect}"}
      case input
      when Array
        # 1) If value is an array, process each item in value recursively using this algorithm,
        #    passing copies of the active context and active property.
        debug("compact") {"Array[#{input.length}]"}
        depth {input.map {|v| compact(v, predicate)}}
      when Hash
        result = Hash.ordered
        input.each do |key, value|
          debug("compact") {"#{key}: #{value.inspect}"}
          compacted_key = context.alias(key)
          debug("compact") {" => compacted key: #{compacted_key.inspect}"} unless compacted_key == key

          case key
          when '@id', '@type'
            # If the key is @id or @type
            result[compacted_key] = case value
            when String, RDF::Value
              # If the value is a string, compact the value according to IRI Compaction.
              context.compact_iri(value, :position => :subject, :depth => @depth).to_s
            when Hash
              # Otherwise, if value is an object containing only the @id key, the compacted value
              # if the result of performing IRI Compaction on that value.
              if value.keys == ["@id"]
                context.compact_iri(value["@id"], :position => :subject, :depth => @depth).to_s
              else
                depth { compact(value, predicate) }
              end
            else
              # Otherwise, the compacted value is the result of performing this algorithm on the value
              # with the current active property.
              depth { compact(value, predicate) }
            end
            debug("compact") {" => compacted value: #{result[compacted_key].inspect}"}
          else
            # Otherwise, if the key is not a keyword, set as active property and compact according to IRI Compaction.
            unless key[0,1] == '@'
              predicate = RDF::URI(key)
              compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)
              debug("compact") {" => compacted key: #{compacted_key.inspect}"}
            end

            # If the value is an object
            compacted_value = if value.is_a?(Hash)
              if value.keys == ['@id'] || value['@value']
                # If the value contains only an @id key or the value contains a @value key, the compacted value
                # is the result of performing Value Compaction on the value.
                debug("compact") {"keys: #{value.keys.inspect}"}
                context.compact_value(predicate, value, :depth => @depth)
              elsif value.keys == ['@list'] && context.container(predicate) == '@list'
                # Otherwise, if the value contains only a @list key, and the active property is subject to list coercion,
                # the compacted value is the result of performing this algorithm on that value.
                debug("compact") {"list"}
                depth {compact(value['@list'], predicate)}
              else
                # Otherwise, the compacted value is the result of performing this algorithm on the value
                debug("compact") {"object"}
                depth {compact(value, predicate)}
              end
            elsif value.is_a?(Array)
              # Otherwise, if the value is an array, the compacted value is the result of performing this algorithm on the value.
              debug("compact") {"array"}
              depth {compact(value, predicate)}
            else
              # Otherwise, the value is already compacted.
              debug("compact") {"value"}
              value
            end
            debug("compact") {" => compacted value: #{compacted_value.inspect}"}
            result[compacted_key || key] = compacted_value
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
