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
        if result.length == 1 && @options[:compactArrays]
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
          # If element has an @value property or element is a node reference, return the result of performing Value Compaction on element using active property.
          v = context.compact_value(property, element, :depth => @depth)
          debug("compact") {"value optimization for #{property}, return as #{v.inspect}"}
          return v
        when '@list'
          # Otherwise, if the active property has a @container mapping to @list and element has a corresponding @list property, recursively compact that property's value passing a copy of the active context and the active property ensuring that the result is an array with all null values removed.
          
          # If there already exists a value for active property in element and the full IRI of property is also coerced to @list, return an error.
          # FIXME: check for full-iri list coercion

          # Otherwise store the resulting array as value of active property if empty or property otherwise.
          compacted_key = context.compact_iri('@list', :position => :predicate, :depth => @depth)
          v = depth { compact(element[k], property) }
          
          # Return either the result as an array, as an object with a key of @list (or appropriate alias from active context
          v = [v].compact unless v.is_a?(Array)
          unless context.container(property) == '@list'
            v = {compacted_key => v}
            if element['@annotation']
              compacted_key = context.compact_iri('@annotation', :position => :predicate, :depth => @depth)
              v[compacted_key] = element['@annotation']
            end
          end
          debug("compact") {"@list result, return as #{v.inspect}"}
          return v
        end

        # Check for property generators before continuing with other elements
        # For each term pg in the active context which is a property generator
        context.mappings.keys.sort.each do |term|
          next unless (expanded_iris = context.mapping(term)).is_a?(Array)
          # Using the first expanded IRI p associated with the property generator
          p = expanded_iris.first.to_s
          
          # Skip to the next property generator term unless p is a property of element
          next unless element.has_key?(p)

          debug("compact") {"check pg #{term}: #{expanded_iris}"}

          # For each node n which is a value of p in element
          node_values = []
          element[p].dup.each do |n|
            # For each expanded IRI pi associated with the property generator other than p
            next unless expanded_iris[1..-1].all? do |pi|
              debug("compact") {"check #{pi} for (#{n.inspect})"}
              element.has_key?(pi) && element[pi].values.any? do |ni|
                nodesEquivalent(n, ni)
              end
            end

            # Remove n as a value of all p and pi in element
            debug("compact") {"removed matched value #{n.inspect} from #{expanded_iris.inspect}"}
            expanded_iris.each do |pi|
              # FIXME: This removes all values equivalent to n, not just the first
              element[p] = element[p].reject {|ni| nodesEquivalent(n, ni)}
            end
              
            # Add the result of performing the compaction algorithm on n to pg to output
            node_values << n
          end
          
          # If there are node_values, or all the values from expanded_iris are empty, add node_values to result, and remove the expanded_iris as keys from element
          if node_values.length > 0 || expanded_iris.all? {|pi| element.has_key?(pi) && element[pi].empty?}
            debug("compact") {"compact extracted pg values"}
            result[term] = depth { compact(node_values, term)}
            debug("compact") {"remove empty pg keys from element"}
            expanded_iris.each do |pi|
              debug(" =>") {"#{pi}? #{lement.fetch(pi, []).empty?}"}
              element.delete(pi) if element.fetch(pi, []).empty?
            end
          end
        end

        # Otherwise, for each property and value in element:
        element.each do |key, value|
          debug("compact") {"#{key}: #{value.inspect}"}

          if %(@id @type).include?(key)
            position = key == '@id' ? :subject : :type
            compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)

            result[compacted_key] = case value
            when String
              # If value is a string, the compacted value is the result of performing IRI Compaction on value.
              debug {" => compacted string for #{key}"}
              context.compact_iri(value, :position => position, :depth => @depth)
            when Array
              # Otherwise, value must be an array. Perform IRI Compaction on every entry of value. If value contains just one entry, value is set to that entry
              compacted_value = value.map {|v2| context.compact_iri(v2, :position => position, :depth => @depth)}
              debug {" => compacted value(#{key}): #{compacted_value.inspect}"}
              compacted_value = compacted_value.first if compacted_value.length == 1 && @options[:compactArrays]
              compacted_value
            end
          elsif key == '@annotation' && context.container(property) == '@annotation'
            # Skip the annotation key if annotations being applied
            next
          else
            if value.empty?
              # Make sure that an empty array is preserved
              compacted_key = context.compact_iri(key, :position => :predicate, :depth => @depth)
              next if compacted_key.nil?
              result[compacted_key] = value
              next
            end

            # For each item in value:
            value = [value] if key == '@annotation' && value.is_a?(String)
            raise ProcessingError, "found #{value.inspect} for #{key} of #{element.inspect}" unless value.is_a?(Array)
            value.each do |item|
              compacted_key = context.compact_iri(key, :position => :predicate, :value => item, :depth => @depth)

              # Result for this item, typically the output object itself
              item_result = result
              item_key = compacted_key
              debug {" => compacted key: #{compacted_key.inspect} for #{item.inspect}"}
              next if compacted_key.nil?

              # Language maps and annotations
              if field = %w(@language @annotation).detect {|kk| context.container(compacted_key) == kk}
                item_result = result[compacted_key] ||= Hash.new
                item_key = item[field]
              end

              compacted_item = depth {self.compact(item, compacted_key)}
              debug {" => compacted value: #{compacted_value.inspect}"}
            
              case item_result[item_key]
              when Array
                item_result[item_key] << compacted_item
              when nil
                if !compacted_value.is_a?(Array) && context.container(compacted_key) == '@set'
                  compacted_item = [compacted_item].compact
                  debug {" => as @set: #{compacted_item.inspect}"}
                end
                item_result[item_key] = compacted_item
              else
                item_result[item_key] = [item_result[item_key], compacted_item]
              end
            end
          end
        end

        # Re-order result keys
        r = Hash.ordered
        result.keys.kw_sort.each {|kk| r[kk] = result[kk]}
        r
      else
        # For other types, the compacted value is the element value
        debug("compact") {element.class.to_s}
        element
      end
    end
  end
end
