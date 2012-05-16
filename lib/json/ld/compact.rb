module JSON::LD
  module Compact
    include Utils

    ##
    # Compact an expanded Array or Hash given an active property and a context.
    #
    # @param [Array, Hash] element
    # @param [String] property (nil)
    # @return [Array, Hash]
    def compact(element, property = nil)
      if property.nil?
        debug("compact") {"element: #{element.inspect}, ec: #{context.inspect}"}
      else
        debug("compact") {"property: #{property.inspect}"}
      end
      case element
      when Array
        # 1) If value is an array, process each item in value recursively using
        #    this algorithm, passing copies of the active context and the
        #    active property.
        debug("compact") {"Array #{element.inspect}"}
        result = depth {element.map {|v| compact(v, property)}}
        
        # If element has a single member and the active property has no
        # @container mapping to @list or @set, the compacted value is that
        # member; otherwise the compacted value is element
        if result.length == 1
          debug("=> extract single element: #{result.first.inspect}")
          result.first
        else
          debug("=> array result: #{result.inspect}")
          result
        end
      when Hash
        # 2) Otherwise, if element is an object:
        result = {}
        
        if k = %w(@list @set @value).detect {|container| element.has_key?(container)}
          debug("compact") {"#{k}: container(#{property}) = #{context.container(property)}"}
        end

        k ||= '@id' if element.keys == ['@id']
        
        case k
        when '@value', '@id'
          # If element has an @value property or element is a subject reference, return the result of performing
          # Value Compaction on element using active property.
          v = context.compact_value(property, element, :depth => @depth)
          debug("compact") {"value optimization, return as #{v.inspect}"}
          return v
        when '@list'
          # Otherwise, if the active property has a @container mapping to @list and element has a corresponding @list property, recursively compact that property's value passing a copy of the active context and the active property ensuring that the result is an array and removing null values.
          compacted_key = context.compact_iri(k, :position => :predicate, :depth => @depth)
          v = depth { compact(element[k], property) }
          
          # Return either the result as an array, as an object with a key of @list (or appropriate alias from active context
          v = [v].compact unless v.is_a?(Array)
          v = {compacted_key => v} unless context.container(property) == k
          debug("compact") {"@list result, return as #{v.inspect}"}
          return v
        end

        # Otherwise, for each property and value in element:
        element.each do |key, value|
          debug("compact") {"#{key}: #{value.inspect}"}

          if %(@id @type).include?(key)
            compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)

            result[compacted_key] = case value
            when String
              # If value is a string, the compacted value is the result of performing IRI Compaction on value.
              debug {" => compacted string for #{key}"}
              context.compact_iri(value, :position => :subject, :depth => @depth)
            when Array
              # Otherwise, value must be an array. Perform IRI Compaction on every entry of value. If value contains just one entry, value is set to that entry
              compacted_value = value.map {|v| context.compact_iri(v, :position => :subject, :depth => @depth)}
              debug {" => compacted value(#{key}): #{compacted_value.inspect}"}
              compacted_value = compacted_value.first if compacted_value.length == 1
              compacted_value
            end
          else
            if value.empty?
              # Make sure that an empty array is preserved
              compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)
              next if compacted_key.nil?
              result[compacted_key] = value
            end

            # For each item in value:
            raise ProcessingError, "found #{value.inspect} for #{key} if #{element.inspect}" unless value.is_a?(Array)
            value.each do |item|
              compacted_key = context.compact_iri(key, :position => :predicate, :value => item, :depth => @depth)
              debug {" => compacted key: #{compacted_key.inspect} for #{item.inspect}"}
              next if compacted_key.nil?

              compacted_item = depth {self.compact(item, compacted_key)}
              debug {" => compacted value: #{compacted_value.inspect}"}
            
              case result[compacted_key]
              when Array
                result[compacted_key] << compacted_item
              when nil
                if !compacted_value.is_a?(Array) && context.container(compacted_key) == '@set'
                  compacted_item = [compacted_item].compact
                  debug {" => as @set: #{compacted_item.inspect}"}
                end
                result[compacted_key] = compacted_item
              else
                result[compacted_key] = [result[compacted_key], compacted_item]
              end
            end
          end
        end
        
        # Re-order result keys
        r = Hash.ordered
        result.keys.sort.each {|k| r[k] = result[k]}
        r
      else
        # For other types, the compacted value is the element value
        debug("compact") {element.class.to_s}
        element
      end
    end
  end
end
