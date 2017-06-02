# -*- encoding: utf-8 -*-
# frozen_string_literal: true
module JSON::LD
  module Compact
    include Utils

    ##
    # This algorithm compacts a JSON-LD document, such that the given context is applied. This must result in shortening any applicable IRIs to terms or compact IRIs, any applicable keywords to keyword aliases, and any applicable JSON-LD values expressed in expanded form to simple values such as strings or numbers.
    #
    # @param [Array, Hash] element
    # @param [String] property (nil)
    # @return [Array, Hash]
    def compact(element, property: nil)
      #if property.nil?
      #  log_debug("compact") {"element: #{element.inspect}, ec: #{context.inspect}"}
      #else
      #  log_debug("compact") {"property: #{property.inspect}"}
      #end

      # If the term definition for active property itself contains a context, use that for compacting values.
      input_context = self.context
      td = self.context.term_definitions[property] if property
      self.context = (td && td.context && self.context.parse(td.context)) || input_context

      case element
      when Array
        #log_debug("") {"Array #{element.inspect}"}
        result = element.map {|item| compact(item, property: property)}.compact

        # If element has a single member and the active property has no
        # @container mapping to @list or @set, the compacted value is that
        # member; otherwise the compacted value is element
        if result.length == 1 && !context.as_array?(property) && @options[:compactArrays]
          #log_debug("=> extract single element: #{result.first.inspect}")
          result.first
        else
          #log_debug("=> array result: #{result.inspect}")
          result
        end
      when Hash
        # Otherwise element is a JSON object.

        # @null objects are used in framing
        return nil if element.has_key?('@null')

        if element.keys.any? {|k| %w(@id @value).include?(k)}
          result = context.compact_value(property, element, log_depth: @options[:log_depth])
          unless result.is_a?(Hash)
            #log_debug("") {"=> scalar result: #{result.inspect}"}
            return result
          end
        end

        inside_reverse = property == '@reverse'
        result, nest_result = {}, nil

        element.keys.sort.each do |expanded_property|
          expanded_value = element[expanded_property]
          #log_debug("") {"#{expanded_property}: #{expanded_value.inspect}"}

          if %w(@id @type).include?(expanded_property)
            compacted_value = [expanded_value].flatten.compact.map do |expanded_type|
              context.compact_iri(expanded_type, vocab: (expanded_property == '@type'), log_depth: @options[:log_depth])
            end

            # If key is @type and any compacted value is a term having a local context, overlay that context.
            if expanded_property == '@type'
              compacted_value.each do |term|
                term_context = self.context.term_definitions[term].context if context.term_definitions[term]
                self.context = context.parse(term_context) if term_context
              end
            end

            compacted_value = compacted_value.first if compacted_value.length == 1

            al = context.compact_iri(expanded_property, vocab: true, quiet: true)
            #log_debug(expanded_property) {"result[#{al}] = #{compacted_value.inspect}"}
            result[al] = compacted_value
            next
          end

          if expanded_property == '@reverse'
            compacted_value = compact(expanded_value, property: '@reverse')
            #log_debug("@reverse") {"compacted_value: #{compacted_value.inspect}"}
            compacted_value.each do |prop, value|
              if context.reverse?(prop)
                value = [value] if !value.is_a?(Array) &&
                  (context.as_array?(prop) || !@options[:compactArrays])
                #log_debug("") {"merge #{prop} => #{value.inspect}"}

                merge_compacted_value(result, prop, value)
                compacted_value.delete(prop)
              end
            end

            unless compacted_value.empty?
              al = context.compact_iri('@reverse', quiet: true)
              #log_debug("") {"remainder: #{al} => #{compacted_value.inspect}"}
              result[al] = compacted_value
            end
            next
          end

          if expanded_property == '@preserve'
            # Compact using `property`
            compacted_value = compact(expanded_value, property: property)
            #log_debug("@preserve") {"compacted_value: #{compacted_value.inspect}"}

            unless compacted_value.is_a?(Array) && compacted_value.empty?
              result['@preserve'] = compacted_value
            end
            next
          end

          if expanded_property == '@index' && context.container(property) == '@index'
            #log_debug("@index") {"drop @index"}
            next
          end

          # Otherwise, if expanded property is @index, @value, or @language:
          if %w(@index @value @language).include?(expanded_property)
            al = context.compact_iri(expanded_property, vocab: true, quiet: true)
            #log_debug(expanded_property) {"#{al} => #{expanded_value.inspect}"}
            result[al] = expanded_value
            next
          end

          if expanded_value == []
            item_active_property =
              context.compact_iri(expanded_property,
                                  value: expanded_value,
                                  vocab: true,
                                  reverse: inside_reverse,
                                  log_depth: @options[:log_depth])

            if nest_prop = context.nest(item_active_property)
              result[nest_prop] ||= {}
              iap = result[result[nest_prop]] ||= []
              result[nest_prop][item_active_property] = [iap] unless iap.is_a?(Array)
            else
              iap = result[item_active_property] ||= []
              result[item_active_property] = [iap] unless iap.is_a?(Array)
            end
          end

          # At this point, expanded value must be an array due to the Expansion algorithm.
          expanded_value.each do |expanded_item|
            item_active_property =
              context.compact_iri(expanded_property,
                                  value: expanded_item,
                                  vocab: true,
                                  reverse: inside_reverse,
                                  log_depth: @options[:log_depth])


            nest_result = if nest_prop = context.nest(item_active_property)
              # FIXME??: It's possible that nest_prop will be used both for nesting, and for values of @nest
              result[nest_prop] ||= {}
            else
              result
            end

            container = context.container(item_active_property)
            as_array = context.as_array?(item_active_property)
            value = list?(expanded_item) ? expanded_item['@list'] : expanded_item
            compacted_item = compact(value, property: item_active_property)
            #log_debug("") {" => compacted key: #{item_active_property.inspect} for #{compacted_item.inspect}"}

            if list?(expanded_item)
              compacted_item = [compacted_item] unless compacted_item.is_a?(Array)
              unless container == '@list'
                al = context.compact_iri('@list', vocab: true, quiet: true)
                compacted_item = {al => compacted_item}
                if expanded_item.has_key?('@index')
                  key = context.compact_iri('@index', vocab: true, quiet: true)
                  compacted_item[key] = expanded_item['@index']
                end
              else
                raise JsonLdError::CompactionToListOfLists,
                      "key cannot have more than one list value" if nest_result.has_key?(item_active_property)
              end
            end

            if %w(@language @index @id @type).include?(container)
              map_object = nest_result[item_active_property] ||= {}
              compacted_item = case container
              when '@id'
                id_prop = context.compact_iri('@id', vocab: true, quiet: true)
                map_key = compacted_item[id_prop]
                map_key = context.compact_iri(map_key, quiet: true)
                compacted_item.delete(id_prop)
                compacted_item
              when '@index'
                map_key = expanded_item[container]
                compacted_item
              when '@language'
                map_key = expanded_item[container]
                value?(expanded_item) ? expanded_item['@value'] : compacted_item
              when '@type'
                type_prop = context.compact_iri('@type', vocab: true, quiet: true)
                map_key, *types = Array(compacted_item[type_prop])
                map_key = context.compact_iri(map_key, vocab: true, quiet: true)
                case types.length
                when 0 then compacted_item.delete(type_prop)
                when 1 then compacted_item[type_prop] = types.first
                else        compacted_item[type_prop] = types
                end
                compacted_item
              end
              compacted_item = [compacted_item] if as_array && !compacted_item.is_a?(Array)
              merge_compacted_value(map_object, map_key, compacted_item)
            else
              compacted_item = [compacted_item] if
                !compacted_item.is_a?(Array) && (!@options[:compactArrays] || as_array)
              merge_compacted_value(nest_result, item_active_property, compacted_item)
            end
          end
        end

        # Re-order result keys
        result.keys.kw_sort.inject({}) {|map, kk| map[kk] = result[kk]; map}
      else
        # For other types, the compacted value is the element value
        #log_debug("compact") {element.class.to_s}
        element
      end

    ensure
      self.context = input_context
    end
  end
end
