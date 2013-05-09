module JSON::LD
  module Compact
    include Utils

    ##
    # This algorithm compacts a JSON-LD document, such that the given context is applied. This must result in shortening any applicable IRIs to terms or compact IRIs, any applicable keywords to keyword aliases, and any applicable JSON-LD values expressed in expanded form to simple values such as strings or numbers.
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
        debug("compact") {"Array #{element.inspect}"}
        result = depth {element.map {|item| compact(item, property)}.compact}

        # If element has a single member and the active property has no
        # @container mapping to @list or @set, the compacted value is that
        # member; otherwise the compacted value is element
        if result.length == 1 && context.container(property).nil? && @options[:compactArrays]
          debug("=> extract single element: #{result.first.inspect}")
          result.first
        else
          debug("=> array result: #{result.inspect}")
          result
        end
      when Hash
        # Otherwise element is a JSON object.

        if element.keys.any? {|k| %w(@id @value).include?(k)}
          result = depth {context.compact_value(property, element)}
          unless result.is_a?(Hash)
            debug("=> scalar result: #{result.inspect}")
            return result
          end
        end

        inside_reverse = property == '@reverse'
        result = {}

        element.keys.each do |expanded_property|
          expanded_value = element[expanded_property]
          debug("compact") {"#{expanded_property}: #{expanded_value.inspect}"}

          if %w(@id @type).include?(expanded_property)
            compacted_value = [expanded_value].flatten.compact.map do |expanded_type|
              depth {context.compact_iri(expanded_type, :vocab => true)}
            end
            compacted_value = compacted_value.first if compacted_value.length == 1

            al = context.compact_iri(expanded_property, :quiet => true)
            debug(expanded_property) {"result[#{al}] = #{compacted_value.inspect}"}
            result[al] = compacted_value
            next
          end

          if expanded_property == '@reverse'
            compacted_value = depth {compact(expanded_value, '@reverse')}
            debug("@reverse") {"compacted_value: #{compacted_value.inspect}"}
            compacted_value.each do |prop, value|
              if context.reverse?(prop)
                value = [value] unless value.is_a?(Array) || @options[:compactArrays]
                debug {"merge #{prop} => #{value.inspect}"}
                merge_value(result, prop, value)
                compacted_value.delete(prop)
              end
            end

            unless compacted_value.empty?
              al = context.compact_iri('@reverse', :quiet => true)
              debug {"remainder: #{al} => #{compacted_value.inspect}"}
              result[al] = compacted_value
              next
            end
          end

          if expanded_property == '@index' && context.container(property) == '@index'
            debug("@index") {"drop @index"}
            next
          end

          # Otherwise, if expanded property is @index, @value, or @language:
          if %w(@index @value @language).include?(expanded_property)
            al = context.compact_iri(expanded_property, :quiet => true)
            debug(expanded_property) {"#{al} => #{expanded_value.inspect}"}
            result[al] = expanded_value
            next
          end

          if expanded_value == []
            item_active_property = depth do
              context.compact_iri(expanded_property,
                                  :value => expanded_value,
                                  :vocab => true,
                                  :reverse => inside_reverse)
            end

            iap = result[item_active_property] ||= []
            result[item_active_property] = [iap] unless iap.is_a?(Array)
          end

          # At this point, expanded value must be an array due to the Expansion algorithm.
          expanded_value.each do |expanded_item|
            item_active_property = depth do
              context.compact_iri(expanded_property,
                                  :value => expanded_item,
                                  :vocab => true,
                                  :reverse => inside_reverse)
            end
            container = context.container(item_active_property)
            value = list?(expanded_item) ? expanded_item['@list'] : expanded_item
            compacted_item = depth {compact(value, item_active_property)}
            debug {" => compacted key: #{item_active_property.inspect} for #{compacted_item.inspect}"}

            if list?(expanded_item)
              compacted_item = [compacted_item] unless compacted_item.is_a?(Array)
              unless container == '@list'
                al = context.compact_iri('@list', :quiet => true)
                compacted_item = {al => compacted_item}
                if expanded_item.has_key?('@index')
                  key = context.compact_iri('@index', :quiet => true)
                  compacted_item[key] = expaned_item['@index']
                end
              else
                raise ProcessingError::CompactionToListOfLists,
                      "key cannot have more than one list value" if result.has_key?(item_active_property)
              end
            end

            if %w(@language @index).include?(container)
              map_object = result.fetch(item_active_property, {})
              compacted_item = compacted_item['@value'] if container == '@language' && value?(compacted_item)
              map_key = expanded_itme[container]
              merge_value(map_object, map_key, compacted_item)
            else
              compacted_item = [compacted_item] if
                !compacted_item.is_a?(Array) && (
                  !@options[:compactArrays] ||
                  %w(@set @list).include?(container) ||
                  %w(@list @graph).include?(expanded_property)
                )
                rp = result[item_active_property]
                if !rp
                  result[item_active_property] = compacted_item
                else
                  result[item_active_property] = [rp] unless rp.is_a?(Array)
                  result[item_active_property].concat([compacted_item].flatten.compact)
                  merge_value(result, item_active_property, compacted_item)
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
