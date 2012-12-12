require 'open-uri'
require 'json'
require 'bigdecimal'

module JSON::LD
  class EvaluationContext
    include Utils

    # The base.
    #
    # @!attribute [rw] base
    # @return [RDF::URI] Document base IRI, used for expanding relative IRIs.
    attr_reader :base

    # @!attribute [rw] context_base
    # @return [RDF::URI] base IRI of the context, if loaded remotely.
    attr_accessor :context_base

    # @!attribute [rw] mappings
    # @return [Hash{String => String}] A list of current, in-scope mappings from term to IRI.
    attr_accessor :mappings

    # @!attribute [rw] iri_to_curie
    # @return [Hash{RDF::URI => String}] Reverse mappings from IRI to a term or CURIE
    attr_accessor :iri_to_curie

    # @!attribute [rw] iri_to_term
    # @return [Hash{RDF::URI => String}] Reverse mappings from IRI to term only for terms, not CURIEs
    attr_accessor :iri_to_term

    # Type coersion
    #
    # The @type keyword is used to specify type coersion rules for the data. For each key in the map, the key is a String representation of the property for which String values will be coerced and the value is the datatype (or @id) to coerce to. Type coersion for the value `@id` asserts that all vocabulary terms listed should undergo coercion to an IRI, including CURIE processing for compact IRI Expressions like `foaf:homepage`.
    #
    # @!attribute [rw] coercions
    # @return [Hash{String => String}]
    attr_accessor :coercions

    # List coercion
    #
    # The @container keyword is used to specify how arrays are to be treated. A value of @list indicates that arrays of values are to be treated as an ordered list. A value of @set indicates that arrays are to be treated as unordered and that singular values are always coerced to an array form on expansion and compaction.
    # @!attribute [rw] containers
    # @return [Hash{String => String}]
    attr_accessor :containers
    
    # Language coercion
    #
    # The @language keyword is used to specify language coercion rules for the data. For each key in the map, the key is a String representation of the property for which String values will be coerced and the value is the language to coerce to. If no property-specific language is given, any default language from the context is used.
    #
    # @!attribute [rw] languages
    # @return [Hash{String => String}]
    attr_accessor :languages
    
    # Default language
    #
    #
    # This adds a language to plain strings that aren't otherwise coerced
    # @!attribute [rw] default_language
    # @return [String]
    attr_accessor :default_language
    
    # Default vocabulary
    #
    # Sets the default vocabulary used for expanding terms which
    # aren't otherwise absolute IRIs
    # @!attribute [rw] vocab
    # @return [String]
    attr_accessor :vocab

    # @!attribute [rw] options
    # @return [Hash{Symbol => Object}] Global options used in generating IRIs
    attr_accessor :options

    # @!attribute [rw] provided_context
    # @return [EvaluationContext] A context provided to us that we can use without re-serializing
    attr_accessor :provided_context

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
    # @param [String, #read, Array, Hash, EvaluatoinContext] context
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
          parse(ctx["@context"] || {})
        rescue JSON::ParserError => e
          debug("parse") {"Failed to parse @context from remote document at #{context}: #{e.message}"}
          raise JSON::LD::InvalidContext::Syntax, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when nil
        debug("parse") {"nil"}
        # Load context document, if it is a string
        ec = EvaluationContext.new(options)
      when String
        debug("parse") {"remote: #{context}, base: #{context_base || base}"}
        # Load context document, if it is a string
        ec = nil
        begin
          url = expand_iri(context, :base => context_base || base, :position => :subject)
          ecdup = self.dup
          ecdup.context_base = url  # Set context_base for recursive remote contexts
          RDF::Util::File.open_file(url) {|f| ec = ecdup.parse(f)}
          ec.provided_context = context
          ec.context_base = url
          debug("parse") {"=> provided_context: #{context.inspect}"}
          ec
        rescue Exception => e
          debug("parse") {"Failed to retrieve @context from remote document at #{context.inspect}: #{e.message}"}
          raise JSON::LD::InvalidContext::LoadError, "Failed to retrieve remote context at #{context.inspect}: #{e.message}", e.backtrace if @options[:validate]
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
        new_ec.provided_context = context.dup

        {
          '@language' => :default_language=,
          '@vocab'    => :vocab=
        }.each do |key, setter|
          v = context.fetch(key, false)
          if v.nil? || v.is_a?(String)
            context.delete(key)
            debug("parse") {"Set #{key} to #{v.inspect}"}
            new_ec.send(setter, v)
          elsif v
            raise InvalidContext::Syntax, "#{key.inspect} is invalid"
          end
        end

        num_updates = 1
        while num_updates > 0 do
          num_updates = 0

          # Map terms to IRIs/keywords first
          context.each do |key, value|
            # Expand a string value, unless it matches a keyword
            debug("parse") {"Hash[#{key}] = #{value.inspect}"}

            if KEYWORDS.include?(key)
              raise InvalidContext::Syntax, "key #{key.inspect} must not be a keyword"
            elsif term_valid?(key)
              # Remove all coercion information for the property
              new_ec.set_coerce(key, nil)
              new_ec.set_container(key, nil)
              @languages.delete(key)

              # Extract IRI mapping. This is complicated, as @id may have been aliased. Also, if @id is explicitly set to nil, it inhibits and automatic mapping, so treat it as false, to distinguish from no mapping at all.
              value = case value
              when Hash
                value.has_key?('@id') && value['@id'].nil? ? false : value.fetch('@id', nil)
              when nil
                false
              else
                value
              end
              raise InvalidContext::Syntax, "unknown mapping for #{key.inspect} to #{value.inspect}" unless (value || "").is_a?(String)

              iri = new_ec.expand_iri(value, :position => :predicate) if value.is_a?(String)
              if iri && new_ec.mappings.fetch(key, nil) != iri
                # Record term definition
                new_ec.set_mapping(key, iri)
                num_updates += 1
              elsif value == false  # Explicitly say this is not mapped
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
                raise InvalidContext::Syntax, "unknown mapping for '@type' to #{value2.inspect}" unless value2.is_a?(String) || value2.nil?
                if new_ec.coerce(key) != iri
                  raise InvalidContext::Syntax, "unknown mapping for '@type' to #{iri.inspect}" unless RDF::URI(iri).absolute? || iri == '@id'
                  # Record term coercion
                  new_ec.set_coerce(key, iri)
                end
              when '@container'
                raise InvalidContext::Syntax, "unknown mapping for '@container' to #{value2.inspect}" unless %w(@list @set @language @annotation).include?(value2)
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
          ctx['@vocab'] = vocab.to_s if vocab

          # Mappings
          mappings.keys.kw_sort{|a, b| a.to_s <=> b.to_s}.each do |k|
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
                dt = compact_iri(dt, :position => :type) unless dt == '@id'
                # Fold into existing definition
                ctx[k]["@type"] = dt
                debug {"=> datatype[#{k}] => #{dt}"}
              end

              debug {"=> container(#{k}) => #{container(k)}"}
              if %w(@list @set @language).include?(container(k))
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
      @mappings.fetch(term.to_s, false)
    end

    ##
    # Set term mapping
    #
    # @param [#to_s] term
    # @param [RDF::URI, String, nil] value
    #
    # @return [RDF::URI, String]
    def set_mapping(term, value)
      term = term.to_s
      term_sym = term.empty? ? "" : term.to_sym
#      raise InvalidContext::Syntax, "mapping term #{term.inspect} must be a string" unless term.is_a?(String)
#      raise InvalidContext::Syntax, "mapping value #{value.inspect} must be an RDF::URI" unless value.nil? || value.to_s[0,1] == '@' || value.is_a?(RDF::URI)
      debug {"map #{term.inspect} to #{value.inspect}"}
      iri_to_term.delete(@mappings[term].to_s) if @mappings[term]
      @mappings[term] = value
      @options[:prefixes][term_sym] = value if @options.has_key?(:prefixes)
      iri_to_term[value.to_s] = term
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
      # @type is always is an IRI
      return '@id' if [RDF.type, '@type'].include?(property)
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
      return '@set' if property == '@graph'
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
    # @option options [:subject, :predicate, :type] position
    #   Useful when determining how to serialize.
    # @option options [RDF::URI] base (self.base)
    #   Base IRI to use when expanding relative IRIs.
    #
    # @return [RDF::URI, String] IRI or String, if it's a keyword
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-expansion
    def expand_iri(iri, options = {})
      return iri unless iri.is_a?(String)
      prefix, suffix = iri.split(':', 2)
      unless (m = mapping(iri)) == false
        # It's an exact match
        debug("expand_iri") {"match: #{iri.inspect} to #{m.inspect}"} unless options[:quiet]
        return m
      end
      debug("expand_iri") {"prefix: #{prefix.inspect}, suffix: #{suffix.inspect}, vocab: #{vocab.inspect}"} unless options[:quiet]
      base = [:subject].include?(options[:position]) ? options.fetch(:base, self.base) : nil
      prefix = prefix.to_s
      case
      when prefix == '_' && suffix          then bnode(suffix)
      when iri.to_s[0,1] == "@"             then iri
      when suffix.to_s[0,2] == '//'         then uri(iri)
      when mappings.fetch(prefix, false)    then uri(mappings[prefix] + suffix.to_s)
      when base                             then base.join(iri)
      when vocab                            then uri("#{vocab}#{iri}")
      else
        # Otherwise, it must be an absolute IRI
        u = uri(iri)
        u if u.absolute? || [:subject].include?(options[:position])
      end
    end

    ##
    # Compacts an absolute IRI to the shortest matching term or compact IRI
    #
    # @param [RDF::URI] iri
    # @param  [Hash{Symbol => Object}] options ({})
    # @option options [:subject, :predicate, :type] position
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
        matched_terms = mappings.keys.select {|t| mapping(t).to_s == iri}
        debug("compact_iri", "initial terms: #{matched_terms.inspect}")

        # Create an empty list of terms _terms_ that will be populated with terms that are ranked according to how closely they match value. Initialize highest rank to 0, and set a flag list container to false.
        terms = {}

        # If value is a @list select terms that match every item equivalently.
        debug("compact_iri", "#{value.inspect} is a list? #{list?(value).inspect}") if value
        if list?(value)
          list_terms = matched_terms.select {|t| container(t) == '@list'}
            
          terms = list_terms.inject({}) do |memo, t|
            memo[t] = term_rank(t, value)
            memo
          end unless list_terms.empty?
          debug("term map") {"remove zero rank terms: #{terms.keys.select {|t| terms[t] == 0}}"} if terms.any? {|t,r| r == 0}
          terms.delete_if {|t, r| r == 0}
        end
        
        # Otherwise, value is @value or a native type.
        # Add a term rank for each term mapping to iri
        # which does not have @container @list
        if terms.empty?
          non_list_terms = matched_terms.reject {|t| container(t) == '@list'}

          # If value is a @list, exclude from term map those terms
          # with @container @set
          non_list_terms.reject {|t| container(t) == '@set'} if list?(value)

          terms = non_list_terms.inject({}) do |memo, t|
            memo[t] = term_rank(t, value)
            memo
          end unless non_list_terms.empty?
          debug("term map") {"remove zero rank terms: #{terms.keys.select {|t| terms[t] == 0}}"} if terms.any? {|t,r| r == 0}
          terms.delete_if {|t, r| r == 0}
        end

        # If we don't want terms, remove anything that's not a CURIE or IRI
        terms.keep_if {|t, v| t.index(':') } if options.fetch(:not_term, false)

        # Find terms having the greatest term match value
        least_distance = terms.values.max
        terms = terms.keys.select {|t| terms[t] == least_distance}

        # If terms is empty, add a compact IRI representation of iri for each 
        # term in the active context which maps to an IRI which is a prefix for 
        # iri where the resulting compact IRI is not a term in the active 
        # context. The resulting compact IRI is the term associated with the 
        # partially matched IRI in the active context concatenated with a colon 
        # (:) character and the unmatched part of iri.
        if terms.empty?
          debug("curies") {"mappings: #{mappings.inspect}"}
          curies = mappings.keys.map do |k|
            debug("curies[#{k}]") {"#{mapping(k).inspect}"}
            #debug("curies[#{k}]") {"#{(mapping(k).to_s.length > 0).inspect}, #{iri.to_s.index(mapping(k).to_s)}"}
            iri.to_s.sub(mapping(k).to_s, "#{k}:") if
              mapping(k).to_s.length > 0 &&
              iri.to_s.index(mapping(k).to_s) == 0 &&
              iri.to_s != mapping(k).to_s
          end.compact

          debug("curies") do
            curies.map do |c|
              "#{c}: " +
              "container: #{container(c).inspect}, " +
              "coerce: #{coerce(c).inspect}, " +
              "lang: #{language(c).inspect}"
            end.inspect
          end

          terms = curies.select do |curie|
            (options[:position] != :predicate || container(curie) != '@list') &&
            coerce(curie).nil? &&
            language(curie) == default_language
          end

          debug("curies") {"selected #{terms.inspect}"}
        end

        # If terms is empty, and the active context has a @vocab which is a  prefix of iri where the resulting relative IRI is not a term in the  active context. The resulting relative IRI is the unmatched part of iri.
        if vocab && terms.empty? && iri.to_s.index(vocab) == 0 &&
           [:predicate, :type].include?(options[:position])
          terms << iri.to_s.sub(vocab, '')
          debug("vocab") {"vocab: #{vocab}, rel: #{terms.first}"}
        end

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

        if terms.empty?
          # If there is a mapping from the complete IRI to null, return null,
          # otherwise, return the complete IRI.
          if mappings.has_key?(iri.to_s) && !mapping(iri)
            debug("iri") {"use nil IRI mapping"}
            terms << nil
          else
            terms << iri.to_s
          end
        end

        # Get the first term based on distance and lexecographical order
        # Prefer terms that don't have @container @set over other terms, unless as set is true
        terms = terms.sort do |a, b|
          debug("term sort") {"c(a): #{container(a).inspect}, c(b): #{container(b)}"}
          if a.to_s.length == b.to_s.length
            a.to_s <=> b.to_s
          else
            a.to_s.length <=> b.to_s.length
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
    # and operates on RHS values, using a supplied key to determine @type and
    # @container coercion rules.
    #
    # @param [String] property
    #   Associated property used to find coercion rules
    # @param [Hash, String] value
    #   Value (literal or IRI) to be expanded
    # @param  [Hash{Symbol => Object}] options
    # @option options [Boolean] :useNativeTypes (true) use native representations
    #
    # @return [Hash] Object representation of value
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-expansion
    def expand_value(property, value, options = {})
      options = {:useNativeTypes => true}.merge(options)
      depth(options) do
        debug("expand_value") {"property: #{property.inspect}, value: #{value.inspect}, coerce: #{coerce(property).inspect}"}
        value = RDF::Literal(value) if RDF::Literal(value).has_datatype?
        dt = case value
        when RDF::Literal
          case value.datatype
          when RDF::XSD.boolean, RDF::XSD.integer, RDF::XSD.double
            # Use appropriate representation for native types
            dtype = value.datatype
            value = if options[:useNativeTypes]
              value.object
            else
              RDF::Literal::Double.new(value, :canonicalize => true).to_s
            end
            dtype
          else
            value
          end
        when
          RDF::Term then value.class.name
        else
          value
        end

        result = if dt || coerce(property)
          {"@value" => value, "@type" => dt || coerce(property)}
        else
          value
        end

        result = case dt
        when RDF::XSD.boolean, RDF::XSD.integer, RDF::XSD.double
          debug("xsd:#{dt.to_s.split('#').last}")
          res = Hash.ordered
          res['@value'] = value
          res['@type'] = coerce(property) if coerce(property)
          res
        when "RDF::URI", "RDF::Node"
          debug("URI | BNode") { value.to_s }
          {'@id' => value.to_s}
        when RDF::Literal
          debug("Literal")
          res = Hash.ordered
          res['@value'] = value.to_s
          res['@type'] = value.datatype.to_s if value.has_datatype?
          res['@language'] = value.language.to_s if value.has_language?
          res
        else
          debug("else")
          case coerce(property)
          when '@id'
            {'@id' => expand_iri(value, :position => :subject).to_s}
          when nil
            debug("expand value") {"lang(prop): #{language(property).inspect}, def: #{default_language.inspect}"}
            language(property) ? {"@value" => value.to_s, "@language" => language(property)} : {"@value" => value.to_s}
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
    # FIXME: revisit the specification version of this.
    def compact_value(property, value, options = {})
      raise ProcessingError::Lossy, "attempt to compact a non-object value: #{value.inspect}" unless value.is_a?(Hash)

      depth(options) do
        debug("compact_value") {"property: #{property.inspect}, value: #{value.inspect}, coerce: #{coerce(property).inspect}"}

        result = case
          #when %w(boolean integer double).any? {|t| expand_iri(value['@type'], :position => :type) == RDF::XSD[t]}
        #  # Compact native type
        #  debug {" (native)"}
        #  l = RDF::Literal(value['@value'], :datatype => expand_iri(value['@type'], :position => :type))
        #  l.canonicalize.object
        when coerce(property) == '@id' && value.has_key?('@id')
          # Compact an @id coercion
          debug {" (@id & coerce)"}
          compact_iri(value['@id'], :position => :subject)
        when value['@type'] && expand_iri(value['@type'], :position => :type) == coerce(property)
          # Compact common datatype
          debug {" (@type & coerce) == #{coerce(property)}"}
          value['@value']
        when value.has_key?('@id')
          # Compact an IRI
          value[self.alias('@id')] = compact_iri(value['@id'], :position => :subject)
          debug {" (#{self.alias('@id')} => #{value['@id']})"}
          value
        when value['@language'] && (value['@language'] == language(property) || container(property) == '@language')
          # Compact language
          debug {" (@language) == #{language(property).inspect}"}
          value['@value']
        when value['@value'] && !value['@value'].is_a?(String)
          # Compact simple literal to string
          debug {" (@value not string)"}
          value['@value']
        when value['@value'] && !value['@language'] && !value['@type'] && !coerce(property) && !default_language
          # Compact simple literal to string
          debug {" (@value && !@language && !@type && !coerce && !language)"}
          value['@value']
        when value['@value'] && !value['@language'] && !value['@type'] && !coerce(property) && !language(property)
          # Compact simple literal to string
          debug {" (@value && !@language && !@type && !coerce && language(property).false)"}
          value['@value']
        when value['@type']
          # Compact datatype
          debug {" (@type)"}
          value[self.alias('@type')] = compact_iri(value['@type'], :position => :type)
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
      default_term = !coerce(term) && !languages.has_key?(term)
      debug("term rank") {
        "term: #{term.inspect}, " +
        "value: #{value.inspect}, " +
        "coerce: #{coerce(term).inspect}, " +
        "lang: #{languages.fetch(term, nil).inspect}/#{language(term).inspect} " +
        "default_term: #{default_term.inspect}"
      }

      # value is null
      rank = if value.nil?
        debug("term rank") { "null value: 3"}
        3
      elsif list?(value)
        if value['@list'].empty?
          # If the @list property is an empty array, if term has @container set to @list, term rank is 1, otherwise 0.
          container(term) == '@list' ? 1 : 0
        else
          # Otherwise, return the greatest rank of all elements in the term.
          depth {value['@list'].map {|v| term_rank(term, v)}.max}
        end
      elsif value?(value)
        val_type = value.fetch('@type', nil)
        val_lang = value['@language'] || false if value.has_key?('@language')
        debug("term rank") {"@val_type: #{val_type.inspect}, val_lang: #{val_lang.inspect}"}
        if val_type
          coerce(term) == val_type ? 3 :  (default_term ? 1 : 0)
        elsif !value['@value'].is_a?(String)
          default_term ? 2 : 1
        elsif val_lang.nil?
          debug("val_lang.nil") {"#{language(term).inspect} && #{coerce(term).inspect}"}
          language(term) == false || (default_term && default_language.nil?) ? 3 : 0
        else
          if val_lang && container(term) == '@language'
            3
          elsif val_lang == language(term) || (default_term && default_language == val_lang)
            2
          elsif default_term
            1
          else
            0
          end
        end
      else # node definition/reference
        coerce(term) == '@id' ? 3 : (default_term ? 1 : 0)
      end
      
      debug(" =>") {rank.inspect}
      rank
    end
  end
end
