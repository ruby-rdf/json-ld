require 'open-uri'
require 'json'
require 'bigdecimal'

module JSON::LD
  class EvaluationContext # :nodoc:
    include Utils

    # The base.
    #
    # The document base IRI, used for expanding relative IRIs.
    #
    # @attr_reader [RDF::URI]
    attr_reader :base

    # A list of current, in-scope mappings from term to IRI.
    #
    # @attr [Hash{String => String}]
    attr :mappings, true

    # Reverse mappings from IRI to a term or CURIE
    #
    # @attr [Hash{RDF::URI => String}]
    attr :iri_to_curie, true

    # Reverse mappings from IRI to term only for terms, not CURIEs
    #
    # @attr [Hash{RDF::URI => String}]
    attr :iri_to_term, true

    # Type coersion
    #
    # The @type keyword is used to specify type coersion rules for the data. For each key in the map, the
    # key is a String representation of the property for which String values will be coerced and
    # the value is the datatype (or @id) to coerce to. Type coersion for
    # the value `@id` asserts that all vocabulary terms listed should undergo coercion to an IRI,
    # including CURIE processing for compact IRI Expressions like `foaf:homepage`.
    #
    # @attr [Hash{String => String}]
    attr :coercions, true

    # List coercion
    #
    # The @container keyword is used to specify how arrays are to be treated.
    # A value of @list indicates that arrays of values are to be treated as an ordered list.
    # A value of @set indicates that arrays are to be treated as unordered and that
    # singular values are always coerced to an array form on expansion and compaction.
    # @attr [Hash{String => String}]
    attr :containers, true
    
    # Language coercion
    #
    # The @language keyword is used to specify language coercion rules for the data. For each key in the map, the
    # key is a String representation of the property for which String values will be coerced and
    # the value is the language to coerce to. If no property-specific language is given,
    # any default language from the context is used.
    #
    # @attr [Hash{String => String}]
    attr :languages, true
    
    # Default language
    #
    #
    # This adds a language to plain strings that aren't otherwise coerced
    # @attr [String]
    attr :default_language, true

    # Global options used in generating IRIs
    # @attr [Hash] options
    attr :options, true

    # A context provided to us that we can use without re-serializing
    attr :provided_context, true

    ##
    # Create new evaluation context
    # @yield [ec]
    # @yieldparam [EvaluationContext]
    # @return [EvaluationContext]
    def initialize(options = {})
      @base = RDF::URI(options[:base]) if options[:base]
      @mappings =  {}
      @coercions = {}
      @containers = {}
      @languages = {}
      @iri_to_curie = {}
      @iri_to_term = {
        RDF.to_uri.to_s => "rdf",
        RDF::XSD.to_uri.to_s => "xsd"
      }

      @options = options

      # Load any defined prefixes
      (options[:prefixes] || {}).each_pair do |k, v|
        @iri_to_term[v.to_s] = k unless k.nil?
      end

      debug("init") {"iri_to_term: #{iri_to_term.inspect}"}
      
      yield(self) if block_given?
    end

    # Create an Evaluation Context using an existing context as a start by parsing the input.
    #
    # @param [String, #read, Array, Hash, EvaluatoinContext] input
    # @return [EvaluationContext] context
    # @raise [InvalidContext]
    #   on a remote context load error, syntax error, or a reference to a term which is not defined.
    def parse(context)
      case context
      when nil
        EvaluationContext.new
      when EvaluationContext
        debug("parse") {"context: #{context.inspect}"}
        context.dup
      when IO, StringIO
        debug("parse") {"io: #{context}"}
        # Load context document, if it is a string
        begin
          ctx = JSON.load(context)
          raise JSON::LD::InvalidContext::Syntax, "missing @context" unless ctx.is_a?(Hash) && ctx["@context"]
          parse(ctx["@context"])
        rescue JSON::ParserError => e
          debug("parse") {"Failed to parse @context from remote document at #{context}: #{e.message}"}
          raise JSON::LD::InvalidContext::Syntax, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when String, nil
        debug("parse") {"remote: #{context}"}
        # Load context document, if it is a string
        ec = nil
        begin
          RDF::Util::File.open_file(context.to_s) {|f| ec = parse(f)}
          ec.provided_context = context
          debug("parse") {"=> provided_context: #{context.inspect}"}
          ec
        rescue Exception => e
          debug("parse") {"Failed to retrieve @context from remote document at #{context}: #{e.message}"}
          raise JSON::LD::InvalidContext::LoadError, "Failed to parse remote context at #{context}: #{e.message}", e.backtrace if @options[:validate]
          self.dup
        end
      when Array
        # Process each member of the array in order, updating the active context
        # Updates evaluation context serially during parsing
        debug("parse") {"Array"}
        ec = self
        context.each {|c| ec = ec.parse(c)}
        ec.provided_context = context
        debug("parse") {"=> provided_context: #{context.inspect}"}
        ec
      when Hash
        new_ec = self.dup
        new_ec.provided_context = context
        
        num_updates = 1
        while num_updates > 0 do
          num_updates = 0

          # Map terms to IRIs/keywords first
          context.each do |key, value|
            # Expand a string value, unless it matches a keyword
            debug("parse") {"Hash[#{key}] = #{value.inspect}"}
            if key == '@language' && (value.nil? || value.is_a?(String))
              new_ec.default_language = value
            elsif term_valid?(key)
              # Remove all coercion information for the property
              new_ec.set_coerce(key, nil)
              new_ec.set_container(key, nil)
              @languages.delete(key)

              # Extract IRI mapping. This is complicated, as @id may have been aliased
              value = value.fetch('@id', nil) if value.is_a?(Hash)
              raise InvalidContext::Syntax, "unknown mapping for #{key.inspect} to #{value.class}" unless value.is_a?(String) || value.nil?

              iri = new_ec.expand_iri(value, :position => :predicate) if value.is_a?(String)
              if iri && KEYWORDS.include?(key)
                raise InvalidContext::Syntax, "key #{key.inspect} must not be a keyword"
              elsif iri && new_ec.mappings.fetch(key, nil) != iri
                # Record term definition
                new_ec.set_mapping(key, iri)
                num_updates += 1
              elsif value.nil?
                new_ec.set_mapping(key, nil)
              end
            else
              raise InvalidContext::Syntax, "key #{key.inspect} is invalid"
            end
          end
        end

        # Next, look for coercion using new_ec
        context.each do |key, value|
          # Expand a string value, unless it matches a keyword
          debug("parse") {"coercion/list: Hash[#{key}] = #{value.inspect}"}
          case value
          when Hash
            # Must have one of @id, @language, @type or @container
            raise InvalidContext::Syntax, "mapping for #{key.inspect} missing one of @id, @language, @type or @container" if (%w(@id @language @type @container) & value.keys).empty?
            value.each do |key2, value2|
              iri = new_ec.expand_iri(value2, :position => :predicate) if value2.is_a?(String)
              case key2
              when '@type'
                raise InvalidContext::Syntax, "unknown mapping for '@type' to #{value2.class}" unless value2.is_a?(String) || value2.nil?
                if new_ec.coerce(key) != iri
                  raise InvalidContext::Syntax, "unknown mapping for '@type' to #{iri.inspect}" unless RDF::URI(iri).absolute? || iri == '@id'
                  # Record term coercion
                  new_ec.set_coerce(key, iri)
                end
              when '@container'
                raise InvalidContext::Syntax, "unknown mapping for '@container' to #{value2.class}" unless %w(@list @set).include?(value2)
                if new_ec.container(key) != value2
                  debug("parse") {"container #{key.inspect} as #{value2.inspect}"}
                  new_ec.set_container(key, value2)
                end
              when '@language'
                if !new_ec.languages.has_key?(key) || new_ec.languages[key] != value2
                  debug("parse") {"language #{key.inspect} as #{value2.inspect}"}
                  new_ec.set_language(key, value2)
                end
              end
            end
          
            # If value has no @id, create a mapping from key
            # to the expanded key IRI
            unless value.has_key?('@id')
              iri = new_ec.expand_iri(key, :position => :predicate)
              new_ec.set_mapping(key, iri)
            end
          when nil, String
            # handled in previous loop
          else
            raise InvalidContext::Syntax, "attempt to map #{key.inspect} to #{value.class}"
          end
        end

        new_ec
      end
    end

    ##
    # Generate @context
    #
    # If a context was supplied in global options, use that, otherwise, generate one
    # from this representation.
    #
    # @param  [Hash{Symbol => Object}] options ({})
    # @return [Hash]
    def serialize(options = {})
      depth(options) do
        use_context = if provided_context
          debug "serlialize: reuse context: #{provided_context.inspect}"
          provided_context
        else
          debug("serlialize: generate context")
          debug {"=> context: #{inspect}"}
          ctx = Hash.ordered
          ctx['@language'] = default_language.to_s if default_language

          # Mappings
          mappings.keys.sort{|a, b| a.to_s <=> b.to_s}.each do |k|
            next unless term_valid?(k.to_s)
            debug {"=> mappings[#{k}] => #{mappings[k]}"}
            ctx[k] = mappings[k].to_s
          end

          unless coercions.empty? && containers.empty? && languages.empty?
            # Coerce
            (coercions.keys + containers.keys + languages.keys).uniq.sort.each do |k|
              next if k == '@type'

              # Turn into long form
              ctx[k] ||= Hash.ordered
              if ctx[k].is_a?(String)
                defn = Hash.ordered
                defn["@id"] = compact_iri(ctx[k], :position => :subject, :not_term => true)
                ctx[k] = defn
              end

              debug {"=> coerce(#{k}) => #{coerce(k)}"}
              if coerce(k) && !NATIVE_DATATYPES.include?(coerce(k))
                dt = coerce(k)
                dt = compact_iri(dt, :position => :datatype) unless dt == '@id'
                # Fold into existing definition
                ctx[k]["@type"] = dt
                debug {"=> datatype[#{k}] => #{dt}"}
              end

              debug {"=> container(#{k}) => #{container(k)}"}
              if %w(@list @set).include?(container(k))
                ctx[k]["@container"] = container(k)
                debug {"=> container[#{k}] => #{container(k).inspect}"}
              end

              debug {"=> language(#{k}) => #{language(k)}"}
              if language(k) != default_language
                ctx[k]["@language"] = language(k) ? language(k) : nil
                debug {"=> language[#{k}] => #{language(k).inspect}"}
              end
              
              # Remove an empty definition
              ctx.delete(k) if ctx[k].empty?
            end
          end

          debug {"start_doc: context=#{ctx.inspect}"}
          ctx
        end

        # Return hash with @context, or empty
        r = Hash.ordered
        r['@context'] = use_context unless use_context.nil? || use_context.empty?
        r
      end
    end
    
    ##
    # Retrieve term mapping
    #
    # @param [String, #to_s] term
    #
    # @return [RDF::URI, String]
    def mapping(term)
      @mappings.fetch(term.to_s, nil)
    end

    ##
    # Set term mapping
    #
    # @param [String] term
    # @param [RDF::URI, String] value
    #
    # @return [RDF::URI, String]
    def set_mapping(term, value)
#      raise InvalidContext::Syntax, "mapping term #{term.inspect} must be a string" unless term.is_a?(String)
#      raise InvalidContext::Syntax, "mapping value #{value.inspect} must be an RDF::URI" unless value.nil? || value.to_s[0,1] == '@' || value.is_a?(RDF::URI)
      debug {"map #{term.inspect} to #{value}"} unless @mappings[term] == value
      iri_to_term.delete(@mappings[term].to_s) if @mappings[term]
      if value
        @mappings[term] = value
        @options[:prefixes][term] = value if @options.has_key?(:prefixes)
        iri_to_term[value.to_s] = term
      else
        @mappings.delete(term)
        nil
      end
    end

    ##
    # Reverse term mapping, typically used for finding aliases for keys.
    #
    # Returns either the original value, or a mapping for this value.
    #
    # @example
    #   {"@context": {"id": "@id"}, "@id": "foo"} => {"id": "foo"}
    #
    # @param [RDF::URI, String] value
    # @return [String]
    def alias(value)
      iri_to_term.fetch(value, value)
    end

    ##
    # Retrieve term coercion
    #
    # @param [String] property in unexpanded form
    #
    # @return [RDF::URI, '@id']
    def coerce(property)
      # Map property, if it's not an RDF::Value
      # @type and @graph always is an IRI
      return '@id' if [RDF.type, '@type', '@graph'].include?(property)
      @coercions.fetch(property, nil)
    end

    ##
    # Set term coercion
    #
    # @param [String] property in unexpanded form
    # @param [RDF::URI, '@id'] value
    #
    # @return [RDF::URI, '@id']
    def set_coerce(property, value)
      debug {"coerce #{property.inspect} to #{value.inspect}"} unless @coercions[property.to_s] == value
      if value
        @coercions[property] = value
      else
        @coercions.delete(property)
      end
    end

    ##
    # Retrieve container mapping, add it if `value` is provided
    #
    # @param [String] property in unexpanded form
    # @return [String]
    def container(property)
      @containers.fetch(property.to_s, nil)
    end

    ##
    # Set container mapping
    #
    # @param [String] property
    # @param [String] value one of @list, @set or nil
    # @return [Boolean]
    def set_container(property, value)
      return if @containers[property.to_s] == value
      debug {"coerce #{property.inspect} to #{value.inspect}"} 
      if value
        @containers[property.to_s] = value
      else
        @containers.delete(value)
      end
    end

    ##
    # Retrieve the language associated with a property, or the default language otherwise
    # @return [String]
    def language(property)
      @languages.fetch(property.to_s, @default_language) if !coerce(property)
    end
    
    ##
    # Set language mapping
    #
    # @param [String] property
    # @param [String] value
    # @return [String]
    def set_language(property, value)
      # Use false for nil language
      @languages[property.to_s] = value ? value : false
    end

    ##
    # Determine if `term` is a suitable term.
    # Term may be any valid JSON string.
    #
    # @param [String] term
    # @return [Boolean]
    def term_valid?(term)
      term.is_a?(String)
    end

    ##
    # Expand an IRI. Relative IRIs are expanded against any document base.
    #
    # @param [String] iri
    #   A keyword, term, prefix:suffix or possibly relative IRI
    # @param  [Hash{Symbol => Object}] options
    # @option options [:subject, :predicate, :object, :datatype] position
    #   Useful when determining how to serialize.
    #
    # @return [RDF::URI, String] IRI or String, if it's a keyword
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-expansion
    def expand_iri(iri, options = {})
      return iri unless iri.is_a?(String)
      prefix, suffix = iri.split(':', 2)
      return mapping(iri) if mapping(iri) # If it's an exact match
      debug("expand_iri") {"prefix: #{prefix.inspect}, suffix: #{suffix.inspect}"} unless options[:quiet]
      base = self.base unless [:predicate, :datatype].include?(options[:position])
      prefix = prefix.to_s
      case
      when prefix == '_' && suffix          then debug("=> bnode"); bnode(suffix)
      when iri.to_s[0,1] == "@"             then debug("=> keyword"); iri
      when suffix.to_s[0,2] == '//'         then debug("=> iri"); uri(iri)
      when mappings.has_key?(prefix)        then debug("=> curie"); uri(mappings[prefix] + suffix.to_s)
      when base                             then debug("=> base"); base.join(iri)
      else
        # Otherwise, it must be an absolute IRI
        u = uri(iri)
        debug("=> absolute") {"#{u.inspect} abs? #{u.absolute?.inspect}"}
        u if u.absolute? || [:subject, :object].include?(options[:position])
      end
    end

    ##
    # Compact an IRI
    #
    # @param [RDF::URI] iri
    # @param  [Hash{Symbol => Object}] options ({})
    # @option options [:subject, :predicate, :object, :datatype] position
    #   Useful when determining how to serialize.
    # @option options [Object] :value
    #   Value, used to select among various maps for the same IRI
    # @option options [Boolean] :not_term (false)
    #   Don't return a term, but only a CURIE or IRI.
    #
    # @return [String] compacted form of IRI
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-compaction
    def compact_iri(iri, options = {})
      depth(options) do
        debug {"compact_iri(#{iri.inspect}, #{options.inspect})"}

        value = options.fetch(:value, nil)

        # Get a list of terms which map to iri
        terms = mappings.keys.select {|t| mapping(t).to_s == iri}

        # Create an association term map for terms to their associated
        # term rank.
        term_map = {}

        # If value is a @list add a term rank for each
        # term mapping to iri which has @container @list.
        debug("compact_iri", "#{value.inspect} is a list? #{list?(value).inspect}")
        if list?(value)
          list_terms = terms.select {|t| container(t) == '@list'}
            
          term_map = list_terms.inject({}) do |memo, t|
            memo[t] = term_rank(t, value)
            memo
          end unless list_terms.empty?
          debug("term map") {"remove zero rank terms: #{term_map.keys.select {|t| term_map[t] == 0}}"} if term_map.any? {|t,r| r == 0}
          term_map.delete_if {|t, r| r == 0}
        end
        
        # Otherwise, value is @value or a native type.
        # Add a term rank for each term mapping to iri
        # which does not have @container @list
        if term_map.empty?
          non_list_terms = terms.reject {|t| container(t) == '@list'}

          # If value is a @list, exclude from term map those terms
          # with @container @set
          non_list_terms.reject {|t| container(t) == '@set'} if list?(value)

          term_map = non_list_terms.inject({}) do |memo, t|
            memo[t] = term_rank(t, value)
            memo
          end unless non_list_terms.empty?
          debug("term map") {"remove zero rank terms: #{term_map.keys.select {|t| term_map[t] == 0}}"} if term_map.any? {|t,r| r == 0}
          term_map.delete_if {|t, r| r == 0}
        end

        # If we don't want terms, remove anything that's not a CURIE or IRI
        term_map.keep_if {|t, v| t.index(':') } if options.fetch(:not_term, false)

        # Find terms having the greatest term match value
        least_distance = term_map.values.max
        terms = term_map.keys.select {|t| term_map[t] == least_distance}

        # If the list of found terms is empty, append a compact IRI for
        # each term which is a prefix of iri which does not have
        # @type coercion, @container coercion or @language coercion rules
        # along with the iri itself.
        if terms.empty?
          curies = mappings.keys.map {|k| iri.to_s.sub(mapping(k).to_s, "#{k}:") if
            iri.to_s.index(mapping(k).to_s) == 0 &&
            iri.to_s != mapping(k).to_s}.compact

          debug("curies") do
            curies.map do |c|
              "#{c}: " +
              "container: #{container(c).inspect}, " +
              "coerce: #{coerce(c).inspect}, " +
              "lang: #{language(c).inspect}"
            end.inspect
          end

          terms = curies.select do |curie|
            container(curie) != '@list' &&
            coerce(curie).nil? &&
            language(curie) == default_language
          end

          debug("curies") {"selected #{terms.inspect}"}

          # If we still don't have any terms and we're using standard_prefixes,
          # try those, and add to mapping
          if terms.empty? && @options[:standard_prefixes]
            terms = RDF::Vocabulary.
              select {|v| iri.index(v.to_uri.to_s) == 0}.
              map do |v|
                prefix = v.__name__.to_s.split('::').last.downcase
                set_mapping(prefix, v.to_uri.to_s)
                iri.sub(v.to_uri.to_s, "#{prefix}:").sub(/:$/, '')
              end
            debug("curies") {"using standard prefies: #{terms.inspect}"}
          end

          terms << iri.to_s
        end
        
        # Get the first term based on distance and lexecographical order
        # Prefer terms that don't have @container @set over other terms, unless as set is true
        terms = terms.sort do |a, b|
          debug("term sort") {"c(a): #{container(a).inspect}, c(b): #{container(b)}"}
          if a.length == b.length
            a <=> b
          else
            a.length <=> b.length
          end
        end
        debug("sorted terms") {terms.inspect}
        result = terms.first

        debug {"=> #{result.inspect}"}
        result
      end
    end

    ##
    # Expand a value from compacted to expanded form making the context
    # unnecessary. This method is used as part of more general expansion
    # and operates on RHS values, using a supplied key to determine @type and @container
    # coercion rules.
    #
    # @param [String] property
    #   Associated property used to find coercion rules
    # @param [Hash, String] value
    #   Value (literal or IRI) to be expanded
    # @param  [Hash{Symbol => Object}] options
    #
    # @return [Hash] Object representation of value
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-expansion
    def expand_value(property, value, options = {})
      depth(options) do
        debug("expand_value") {"property: #{property.inspect}, value: #{value.inspect}, coerce: #{coerce(property).inspect}"}
        result = case value
        when TrueClass, FalseClass, RDF::Literal::Boolean
          case coerce(property)
          when RDF::XSD.double.to_s
            {"@value" => value.to_s, "@type" => RDF::XSD.double.to_s}
          else
            # Unless there's coercion, to not modify representation
            value.is_a?(RDF::Literal::Boolean) ? value.object : value
          end
        when Integer, RDF::Literal::Integer
          case coerce(property)
          when RDF::XSD.double.to_s
            {"@value" => RDF::Literal::Double.new(value, :canonicalize => true).to_s, "@type" => RDF::XSD.double.to_s}
          when RDF::XSD.integer.to_s, nil
            # Unless there's coercion, to not modify representation
            value.is_a?(RDF::Literal::Integer) ? value.object : value
          else
            res = Hash.ordered
            res['@value'] = value.to_s
            res['@type'] = coerce(property)
            res
          end
        when Float, RDF::Literal::Double
          case coerce(property)
          when RDF::XSD.integer.to_s
            {"@value" => value.to_int.to_s, "@type" => RDF::XSD.integer.to_s}
          when RDF::XSD.double.to_s
            {"@value" => RDF::Literal::Double.new(value, :canonicalize => true).to_s, "@type" => RDF::XSD.double.to_s}
          when nil
            # Unless there's coercion, to not modify representation
            value.is_a?(RDF::Literal::Double) ? value.object : value
          else
            res = Hash.ordered
            res['@value'] = value.to_s
            res['@type'] = coerce(property)
            res
          end
        when BigDecimal, RDF::Literal::Decimal
          {"@value" => value.to_s, "@type" => RDF::XSD.decimal.to_s}
        when Date, Time, DateTime
          l = RDF::Literal(value)
          {"@value" => l.to_s, "@type" => l.datatype.to_s}
        when RDF::URI, RDF::Node
          {'@id' => value.to_s}
        when RDF::Literal
          res = Hash.ordered
          res['@value'] = value.to_s
          res['@type'] = value.datatype.to_s if value.has_datatype?
          res['@language'] = value.language.to_s if value.has_language?
          res
        else
          case coerce(property)
          when '@id'
            {'@id' => expand_iri(value, :position => :object).to_s}
          when nil
            debug("expand value") {"lang(prop): #{language(property).inspect}, def: #{default_language.inspect}"}
            language(property) ? {"@value" => value.to_s, "@language" => language(property)} : value.to_s
          else
            res = Hash.ordered
            res['@value'] = value.to_s
            res['@type'] = coerce(property).to_s
            res
          end
        end
        
        debug {"=> #{result.inspect}"}
        result
      end
    end

    ##
    # Compact a value
    #
    # @param [String] property
    #   Associated property used to find coercion rules
    # @param [Hash] value
    #   Value (literal or IRI), in full object representation, to be compacted
    # @param  [Hash{Symbol => Object}] options
    #
    # @return [Hash] Object representation of value
    # @raise [ProcessingError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-compaction
    def compact_value(property, value, options = {})
      raise ProcessingError::Lossy, "attempt to compact a non-object value: #{value.inspect}" unless value.is_a?(Hash)

      depth(options) do
        debug("compact_value") {"property: #{property.inspect}, value: #{value.inspect}, coerce: #{coerce(property).inspect}"}

        result = case
        when %w(boolean integer double).any? {|t| expand_iri(value['@type'], :position => :datatype) == RDF::XSD[t]}
          # Compact native type
          debug {" (native)"}
          l = RDF::Literal(value['@value'], :datatype => expand_iri(value['@type'], :position => :datatype))
          l.canonicalize.object
        when coerce(property) == '@id' && value.has_key?('@id')
          # Compact an @id coercion
          debug {" (@id & coerce)"}
          compact_iri(value['@id'], :position => :object)
        when value['@type'] && expand_iri(value['@type'], :position => :datatype) == coerce(property)
          # Compact common datatype
          debug {" (@type & coerce) == #{coerce(property)}"}
          value['@value']
        when value.has_key?('@id')
          # Compact an IRI
          value[self.alias('@id')] = compact_iri(value['@id'], :position => :object)
          debug {" (#{self.alias('@id')} => #{value['@id']})"}
          value
        when value['@language'] && value['@language'] == language(property)
          # Compact language
          debug {" (@language) == #{language(property).inspect}"}
          value['@value']
        when value['@value'] && !value['@language'] && !value['@type'] && !coerce(property) && !default_language
          # Compact simple literal to string
          debug {" (@value && !@language && !@type && !coerce && !language)"}
          value['@value']
        when value['@type']
          # Compact datatype
          debug {" (@type)"}
          value[self.alias('@type')] = compact_iri(value['@type'], :position => :datatype)
          value
        else
          # Otherwise, use original value
          debug {" (no change)"}
          value
        end
        
        # If the result is an object, tranform keys using any term keyword aliases
        if result.is_a?(Hash) && result.keys.any? {|k| self.alias(k) != k}
          debug {" (map to key aliases)"}
          new_element = {}
          result.each do |k, v|
            new_element[self.alias(k)] = v
          end
          result = new_element
        end

        debug {"=> #{result.inspect}"}
        result
      end
    end

    def inspect
      v = %w([EvaluationContext)
      v << "def_language=#{default_language}"
      v << "languages[#{languages.keys.length}]=#{languages}"
      v << "mappings[#{mappings.keys.length}]=#{mappings}"
      v << "coercions[#{coercions.keys.length}]=#{coercions}"
      v << "containers[#{containers.length}]=#{containers}"
      v.join(", ") + "]"
    end
    
    def dup
      # Also duplicate mappings, coerce and list
      ec = super
      ec.mappings = mappings.dup
      ec.coercions = coercions.dup
      ec.containers = containers.dup
      ec.languages = languages.dup
      ec.default_language = default_language
      ec.options = options
      ec.iri_to_term = iri_to_term.dup
      ec.iri_to_curie = iri_to_curie.dup
      ec
    end

    private

    def uri(value, append = nil)
      value = RDF::URI.new(value)
      value = value.join(append) if append
      value.validate! if @options[:validate]
      value.canonicalize! if @options[:canonicalize]
      value = RDF::URI.intern(value) if @options[:intern]
      value
    end

    # Keep track of allocated BNodes
    #
    # Don't actually use the name provided, to prevent name alias issues.
    # @return [RDF::Node]
    def bnode(value = nil)
      @@bnode_cache ||= {}
      @@bnode_cache[value.to_s] ||= RDF::Node.new(value)
    end

    ##
    # Get a "match value" given a term and a value. The value
    # is lowest when the relative match between the term and the value
    # is closest.
    #
    # @param [String] term
    # @param [Object] value
    # @return [Integer]
    def term_rank(term, value)
      debug("term rank") { "term: #{term.inspect}, value: #{value.inspect}"}
      debug("term rank") { "coerce: #{coerce(term).inspect}, lang: #{languages.fetch(term, nil).inspect}"}

      # A term without @language or @type can be used with rank 1 for any value
      default_term = !coerce(term) && !languages.has_key?(term)
      debug("term rank") { "default_term: #{default_term.inspect}"}

      rank = case value
      when TrueClass, FalseClass
        coerce(term) == RDF::XSD.boolean.to_s ? 3 : (default_term ? 2 : 1)
      when Integer
        coerce(term) == RDF::XSD.integer.to_s ? 3 : (default_term ? 2 : 1)
      when Float
        coerce(term) == RDF::XSD.double.to_s ? 3 : (default_term ? 2 : 1)
      when nil
        # A value of null probably means it's an @id
        3
      when String
        # When compacting a string, the string has no language, so the term can be used if the term has @language null or it is a default term and there is no default language
        debug("term rank") {"string: lang: #{languages.fetch(term, false).inspect}, def: #{default_language.inspect}"}
        !languages.fetch(term, true) || (default_term && !default_language) ? 3 : 0
      when Hash
        if list?(value)
          if value['@list'].empty?
            # If the @list property is an empty array, if term has @container set to @list, term rank is 1, otherwise 0.
            container(term) == '@list' ? 1 : 0
          else
            # Otherwise, return the sum of the term ranks for every entry in the list.
            depth {value['@list'].inject(0) {|memo, v| memo + term_rank(term, v)}}
          end
        elsif subject?(value) || subject_reference?(value)
          coerce(term) == '@id' ? 3 : (default_term ? 1 : 0)
        elsif val_type = value.fetch('@type', nil)
          coerce(term) == val_type ? 3 :  (default_term ? 1 : 0)
        elsif val_lang = value.fetch('@language', nil)
          val_lang == language(term) ? 3 : (default_term ? 1 : 0)
        else
          default_term ? 3 : 0
        end
      else
        raise ProcessingError, "Unexpected value for term_rank: #{value.inspect}"
      end
      
      # If term has @container @set, and rank is not 0, increase rank by 1.
      rank > 0 && container(term) == '@set' ? rank + 1 : rank
    end
  end
end