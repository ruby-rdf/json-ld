require 'open-uri'
require 'json'
require 'bigdecimal'

module JSON::LD
  class Context
    include Utils

    # Term Definitions specify how properties and values have to be interpreted as well as the current vocabulary mapping and the default language
    class TermDefinition
      # @!attribute [rw] id
      # @return [String, Array[String]] IRI mapping
      attr_accessor :id

      # @!attribute [rw] type_mapping
      # @return [String] Type mapping
      attr_accessor :type_mapping

      # @!attribute [rw] container_mapping
      # @return [String] Container mapping
      attr_accessor :container_mapping

      # @!attribute [rw] language_mapping
      # @return [String] Language mapping
      attr_accessor :language_mapping

      # Create a new Term Mapping with an ID
      # @param [String, Array[String]] id
      def initialize(id = nil)
        @id = id
      end

      # Is term a property generator?
      def property_generator?; id.is_a?(Array); end

      def dup
        definition = super
        definition.type_mappings = type_mapping.dup
        definition
      end

      # Output Hash or String definition for this definition
      # @return [String, Hash{String => Array[String], String}]
      def to_context_definition
        if language_mapping.nil? && container_mapping.nil? && type_mapping.nil? && !property_generator?
          id
        else
          defn = Hash.ordered
          defn['@id'] = id
          defn['@type'] = type_mapping if type_mapping
          defn['@container'] = container_mapping if container_mapping
          # Language set as false to be output as null
          defn['@language'] = (language_mapping ? language_mapping : nil) unless language_mapping.nil?
          defn
        end
      end
    end

    # The base.
    #
    # @!attribute [rw] base
    # @return [RDF::URI] Document base IRI, used for expanding relative IRIs.
    attr_reader :base

    # @!attribute [rw] context_base
    # @return [RDF::URI] base IRI of the context, if loaded remotely.
    attr_accessor :context_base

    # Term definitions
    # @!attribute [r] term_definitions
    # @return [Hash{String => TermDefinition}]
    attr_reader :term_definitions

    # Keyword aliases. Aliases a keyword to the set of aliases, ordered
    # by size and lexographically
    #
    # @!attribute [r] keyword_aliases
    # @return [Hash{String => Array[String]}]
    attr_reader :keyword_aliases

    # @!attribute [rw] iri_to_term
    # @return [Hash{RDF::URI => String}] Reverse mappings from IRI to term only for terms, not CURIEs
    attr_accessor :iri_to_term

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
    # @return [Context] A context provided to us that we can use without re-serializing
    attr_accessor :provided_context

    # @!attribute [r] remote_contexts
    # @return [Array<String>] The list of remote contexts already processed
    attr_accessor :remote_contexts

    # @!attribute [r] namer
    # @return [BlankNodeNamer]
    attr_accessor :namer

    ##
    # Create new evaluation context
    # @yield [ec]
    # @yieldparam [Context]
    # @return [Context]
    def initialize(options = {})
      @base = RDF::URI(options[:base]) if options[:base]
      @term_definitions = {}
      @keyword_aliases = {}
      @iri_to_term = {
        RDF.to_uri.to_s => "rdf",
        RDF::XSD.to_uri.to_s => "xsd"
      }
      @remote_contexts = []
      @namer = BlankNodeNamer.new("t")

      @options = options

      # Load any defined prefixes
      (options[:prefixes] || {}).each_pair do |k, v|
        @iri_to_term[v.to_s] = k unless k.nil?
      end

      debug("init") {"iri_to_term: #{iri_to_term.inspect}"}
      
      yield(self) if block_given?
    end

    # Create an Evaluation Context
    #
    # When processing a JSON-LD data structure, each processing rule is applied using information provided by the active context. This section describes how to produce an active context.
    #
    # The active context contains the active term definitions which specify how properties and values have to be interpreted as well as the current vocabulary mapping and the default language. Each term definition consists of an IRI mapping and optionally a type mapping from terms to datatypes or language mapping from terms to language codes, and a container mapping. If an IRI mapping maps a term to multiple IRIs it is said to be a property generator. The active context also keeps track of keyword aliases.
    #
    # When processing, the active context is initialized without any term definitions, vocabulary mapping, or default language. If a local context is encountered during processing, a new active context is created by cloning the existing active context. Then the information from the local context is merged into the new active context. A local context is identified within a JSON object by the value of the @context key, which must be a string, an array, or a JSON object.
    #
    # @param [String, #read, Array, Hash, EvaluatoinContext] context
    # @return [Context]
    # @raise [InvalidContext]
    #   on a remote context load error, syntax error, or a reference to a term which is not defined.
    def parse(context)
      case context
      when Context
        debug("parse") {"context: #{context.inspect}"}
        context.dup
      when IO, StringIO
        debug("parse") {"io: #{context}"}
        # Load context document, if it is a string
        begin
          ctx = JSON.load(context)
          raise JSON::LD::InvalidContext::LoadError, "Context missing @context key" if @options[:validate] && ctx['@context'].nil?
          parse(ctx["@context"] || {})
        rescue JSON::ParserError => e
          debug("parse") {"Failed to parse @context from remote document at #{context}: #{e.message}"}
          raise JSON::LD::InvalidContext::Syntax, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when nil
        debug("parse") {"nil"}
        # If context equals null, then set result to a newly-initialized active context
        Context.new(options)
      when String
        debug("parse") {"remote: #{context}, base: #{context_base || base}"}
        # Load context document, if it is a string
        begin
          url = expand_iri(context, :base => context_base || base, :documentRelative => true)
          raise JSON::LD::InvalidContext::LoadError if remote_contexts.include?(url)
          @remote_contexts = @remote_contexts + [url]
          result = self.dup
          result.context_base = url  # Set context_base for recursive remote contexts
          RDF::Util::File.open_file(url) {|f| result = result.parse(f)}
          result.provided_context = context
          result.context_base = url
          debug("parse") {"=> provided_context: #{context.inspect}"}
          result
        rescue Exception => e
          debug("parse") {"Failed to retrieve @context from remote document at #{context.inspect}: #{e.message}"}
          raise JSON::LD::InvalidContext::LoadError, "Failed to retrieve remote context at #{context.inspect}: #{e.message}", e.backtrace if @options[:validate]
          self.dup
        end
      when Array
        # Process each member of the array in order, updating the active context
        # Updates evaluation context serially during parsing
        debug("parse") {"Array"}
        result = self
        context.each {|c| result = result.parse(c)}
        result.provided_context = context
        debug("parse") {"=> provided_context: #{context.inspect}"}
        result
      when Hash
        result = self.dup
        result.provided_context = context.dup

        # Create a JSON object defined to use to keep track of whether or not a term has already been defined or currently being defined during recursion.
        defined = {}

        # If context has a @vocab member: if its value is not a valid absolute IRI or null trigger an INVALID_VOCAB_MAPPING error; otherwise set the active context's vocabulary mapping to its value and remove the @vocab member from context.
        {
          '@language' => :default_language=,
          '@vocab'    => :vocab=
        }.each do |key, setter|
          v = context.fetch(key, false)
          if v.nil? || v.is_a?(String)
            context.delete(key)
            debug("parse") {"Set #{key} to #{v.inspect}"}
            result.send(setter, v)
          elsif v && @options[:validate]
            raise InvalidContext::Syntax, "#{key.inspect} is invalid"
          end
        end

        # For each key-value pair in context invoke the Create Term Definition subalgorithm, passing result for active context, context for local context, key, and defined
        depth do
          context.each do |key, value|
            result.create_term_definition(context, key, defined)
          end
        end

        # Return result
        result
      end
    end

    # Create Term Definition
    #
    # Term definitions are created by parsing the information in the given local context for the given term. If the given term is a compact IRI with a prefix that is a key in the local context, then that prefix is considered a dependency with its own term definition that must first be created, through recursion, before continuing. Because a term definition can depend on other term definitions, a mechanism must be used to detect cyclical dependencies. The solution employed here uses a map, defined, that keeps track of whether or not a term has been defined or is currently in the process of being defined. This map is checked before any recursion is attempted.
    #
    # After all dependencies have been defined, the rest of the information in the local context for the given term is taken into account, creating the appropriate IRI mapping, container mapping, and type mapping or language mapping for the term.
    #
    # @param [Hash] local_context
    # @param [String] term
    # @param [Hash] defined
    # @raise [InvalidContext]
    #   Represents a cyclical term dependency
    def create_term_definition(local_context, term, defined)
      # Expand a string value, unless it matches a keyword
      debug("create_term_definition") {"term = #{term.inspect}"}

      # If defined contains the key term, then the associated value must be true, indicating that the term definition has already been created, so return. Otherwise, a cyclical term definition has been detected, which is an error.
      case defined[term]
      when TrueClass then return
      when nil
        defined[term] = false
      else
        raise "Cyclical term dependency found for #{term.inspect}"
      end

      # Since keywords cannot be overridden, term must not be a keyword. Otherwise, an invalid value has been detected, which is an error.
      if KEYWORDS.include?(term) && !%w(@vocab @language).include?(term)
        raise InvalidContext::Syntax, "term #{term.inspect} must not be a keyword" if @options[:validate]
      elsif !term_valid?(term) && @options[:validate]
        raise InvalidContext::Syntax, "term #{term.inspect} is invalid"
      end

      # Remove any existing term definition for term in active context.
      term_definitions.delete(term)

      # If term is a keyword alias in active context, remove it.
      #if keyword_aliases.values.compact.include?(term)
      #  keyword_aliases.each do |kw, aliases|
      #    keyword_aliases[kw] -= term
      #  end
      #end

      case value = local_context.fetch(term, false)
      when nil, {'@id' => nil}
        # If value equals null or value is a JSON object containing the key-value pair (@id-null), then set the term definition in active context to null, set the value associated with defined's key term to true, and return.
        debug(" =>") {"nil"}
        term_definitions[term] = nil
        defined[term] = true
        return
      when String
        # Expand value by setting it to the result of using the IRI Expansion algorithm, passing active context, value, true for vocabRelative, true for documentRelative, local context, and defined.
        value = depth {expand_iri(value, :documentRelative => true, :vocabRelative => true, :local_context => local_context, :defined => defined)}

        if KEYWORDS.include?(value)
          # If value is a keyword, then value must not be equal to @context or @preserve. Otherwise an invalid keyword alias has been detected, which is an error. Add term to active context as a keyword alias for value. If there is more than one keyword alias for value, then store its aliases as an array, sorted by length, breaking ties lexicographically.
          raise InvalidContext::Syntax, "key #{value.inspect} must not be a @context or @preserve" if %w(@context @preserve).include?(value)
          kw_alias = keyword_aliases[value] ||= []
          keyword_aliases[value] = kw_alias.unshift(term).uniq.term_sort
          debug(" =>") {value}
        end
        # Set the IRI mapping for the term definition for term in active context to value, set the value associated with defined's key term to true, and return.
        term_definitions[term] = TermDefinition.new(value)
        defined[term] = true
        debug(" =>") {value}
      when Hash
        debug("create_term_definition") {"Hash[#{term.inspect}] = #{value.inspect}"}
        definition = TermDefinition.new

        if value.has_key?('@id')
          definition.id = case id = value['@id']
          when Array
            # expand each item according the IRI Expansion algorithm. If an item does not expand to a valid absolute IRI, raise an INVALID_PROPERTY_GENERATOR error; otherwise sort val and store it as IRI mapping in definition.
            id.map do |v|
              raise InvalidContext::Syntax, "unknown mapping for #{term.inspect} to #{v.inspect}" unless v.is_a?(String)
              expand_iri(v, :documentRelative => true, :local_context => local_context, :defined => defined)
            end.sort
          when String
            expand_iri(id, :documentRelative => true, :local_context => local_context, :defined => defined)
          else
            raise InvalidContext::Syntax, "Expected #{term.inspect} definition to be a String or Hash, was #{value}"
          end
        elsif term.include?(':')
          # If term is a compact IRI with a prefix that is a key in local context then a dependency has been found. Use this algorithm recursively passing active context, local context, the prefix as term, and defined.
          prefix, suffix = term.split(':')
          depth {create_term_definition(local_context, prefix, defined)} if local_context.has_key?(prefix)

          definition.id = if td = term_definitions[prefix]
            # If term's prefix has a term definition in active context, set the IRI mapping for definition to the result of concatenating the value associated with the prefix's IRI mapping and the term's suffix.
            td.id + suffix
          else
            # Otherwise, term is an absolute IRI. Set the IRI mapping for definition to term
            term
          end
          debug(" =>") {definition.id}
        else
          # Otherwise, active context must have a vocabulary mapping, otherwise an invalid value has been detected, which is an error. Set the IRI mapping for definition to the result of concatenating the value associated with the vocabulary mapping and term.
          raise InvalidContext::Syntax, "relative term definition without vocab" unless vocab
          definition.id = vocab + value
          debug(" =>") {definition.id}
        end

        if value.has_key?('@type')
          type = value['@type']
          # SPEC FIXME: @type may be nil
          raise InvalidContext::Syntax, "unknown mapping for '@type' to #{type.inspect}" unless type.is_a?(String) || type.nil?
          type = expand_iri(type, :documentRelative => true, :local_context => local_context, :defined => defined) if type.is_a?(String)
          debug("create_term_definition") {"type_mapping: #{type.inspect}"}
          definition.type_mapping = type
        end

        if value.has_key?('@container')
          container = value['@container']
          raise InvalidContext::Syntax, "unknown mapping for '@container' to #{container.inspect}" unless %w(@list @set @language @index).include?(container)
          debug("create_term_definition") {"container_mapping: #{container.inspect}"}
          definition.container_mapping = container
        end

        if value.has_key?('@language')
          language = value['@language']
          raise InvalidContext::Syntax, "language must be null or a string, was #{language.inspect}}" unless language.nil? || (language || "").is_a?(String)
          language = language.downcase if language.is_a?(String)
          debug("create_term_definition") {"language_mapping: #{language.inspect}"}
          definition.language_mapping = language
        end

        term_definitions[term] = definition
      else
        raise InvalidContext::Syntax, "Term definition for #{term.inspect} is an #{value.class}"
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

          # Keyword Aliases
          keyword_aliases.each do |kw, aliases|
            debug {"=> kw_aliases[#{kw}] => #{aliases}"}
            aliases.each {|a| ctx[a] = kw}
          end

          # Term Definitions
          term_definitions.each do |term, definition|
            ctx[term] = definition.to_context_definition
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

    ## FIXME: this should go away
    # Retrieve term mappings
    #
    # @return [Array<String>]
    # @deprecated
    def mappings
      term_definitions.inject({}) do |memo, (t,td)|
        memo[t] = td ? td.id : nil
        memo
      end
    end

    ## FIXME: this should go away
    # Retrieve term mapping
    #
    # @param [String, #to_s] term
    #
    # @return [RDF::URI, String]
    # @deprecated
    def mapping(term)
      term_definitions[term] ? term_definitions[term].id : nil
    end

    ## FIXME: this should go away
    # Set term mapping
    #
    # @param [#to_s] term
    # @param [RDF::URI, String, nil] value
    #
    # @return [RDF::URI, String]
    # @deprecated
    def set_mapping(term, value)
      debug {"map #{term.inspect} to #{value.inspect}"}
      term = term.to_s
      term_definitions[term] = TermDefinition.new(value)

      term_sym = term.empty? ? "" : term.to_sym
      iri_to_term.delete(term_definitions[term].id.to_s) if term_definitions[term].id.is_a?(String)
      @options[:prefixes][term_sym] = value if @options.has_key?(:prefixes)
      iri_to_term[value.to_s] = term
    end

    ## FIXME: this should go away
    # Reverse term mapping, typically used for finding aliases for keys.
    #
    # Returns either the original value, or a mapping for this value.
    #
    # @example
    #   {"@context": {"id": "@id"}, "@id": "foo"} => {"id": "foo"}
    #
    # @param [RDF::URI, String] value
    # @return [String]
    # @deprecated
    def alias(value)
      iri_to_term.fetch(value, value)
    end

    ## FIXME: this should go away
    # Retrieve type mappings
    #
    # @return [Array<String>]
    # @deprecated
    def coercions
      term_definitions.inject({}) do |memo, (t,td)|
        memo[t] = td.type_mapping
        memo
      end
    end

    ##
    # Retrieve term coercion
    #
    # @param [String] property in unexpanded form
    #
    # @return [RDF::URI, '@id']
    # @deprecated
    def coerce(property)
      # Map property, if it's not an RDF::Value
      # @type is always is an IRI
      return '@id' if [RDF.type, '@type'].include?(property)
      term_definitions[property].type_mapping if term_definitions.has_key?(property)
    end

    ##
    # Set term coercion
    #
    # @param [String] property in unexpanded form
    # @param [RDF::URI, '@id'] value
    #
    # @return [RDF::URI, '@id']
    # @deprecated
    def set_coerce(property, value)
      debug {"coerce #{property.inspect} to #{value.inspect}"} unless term_definitions[property.to_s].type_mapping == value
      term_definitions[property.to_s].type_mapping = value
    end

    ## FIXME: this should go away
    # Retrieve container mappings
    #
    # @return [Array<String>]
    # @deprecated
    def containers
      term_definitions.inject({}) do |memo, (t,td)|
        memo[t] = td.container_mapping
        memo
      end
    end

    ##
    # Retrieve container mapping, add it if `value` is provided
    #
    # @param [String] property in unexpanded form
    # @return [String]
    # @deprecated
    def container(property)
      return '@set' if property == '@graph'
      term_definitions[property.to_s].container_mapping if term_definitions.has_key?(property)
    end

    ##
    # Set container mapping
    #
    # @param [String] property
    # @param [String] value one of @list, @set or nil
    # @return [Boolean]
    # @deprecated
    def set_container(property, value)
      debug {"coerce #{property.inspect} to #{value.inspect}"}
      raise "Can't set container mapping with no term definition" unless term_definitions.has_key?(property.to_s)
      term_definitions[property.to_s].container_mapping = value
    end

    ## FIXME: this should go away
    # Retrieve language mappings
    #
    # @return [Array<String>]
    # @deprecated
    def languages
      term_definitions.inject({}) do |memo, (t,td)|
        memo[t] = td.language_mapping
        memo
      end
    end

    ##
    # Retrieve the language associated with a property, or the default language otherwise
    # @return [String]
    # @deprecated
    def language(property)
      raise "Can't set language mapping with no term definition" unless term_definitions.has_key?(property.to_s)
      lang = term_definitions[property.to_s].language_mapping if term_definitions.has_key?(property)
      lang || @default_language
    end
    
    ##
    # Set language mapping
    #
    # @param [String] property
    # @param [String] value
    # @return [String]
    def set_language(property, value)
      # Use false for nil language
      term_definitions[property.to_s].language_mapping = value ? value : false
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
    #   Useful when determining how to serialize (deprecated).
    # @option options [RDF::URI] base (self.base)
    #   Base IRI to use when expanding relative IRIs (deprecated).
    # @option options [Array<String>] path ([])
    #   Array of looked up iris, used to find cycles (deprecated).
    # @option options [Boolean] documentRelative (false)
    # @option options [Boolean] vocabRelative (false)
    # @option options [Context] local_context
    #   Used during Context Processing.
    # @option options [Hash] defined
    #   Used during Context Processing.
    # @return [String, Array<String>]
    #   IRI or String, if it's a keyword, or array of IRI, if it matches
    #   a property generator
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-expansion
    def expand_iri(value, options = {})
      return value unless value.is_a?(String)

      return value if KEYWORDS.include?(value) # FIXME: Spec bug: otherwise becomes relative
      local_context = options[:local_context]
      defined = options.fetch(:defined, {})

      # If local context is not null, it contains a key that equals value, and the value associated with the key that equals value in defined is not true, then invoke the Create Term Definition subalgorithm, passing active context, local context, value as term, and defined. This will ensure that a term definition is created for value in active context during Context Processing.
      if local_context && local_context.has_key?(value) && !defined[value]
        depth {create_term_definition(local_context, value, defined)}
      end

      # If local context is not null then active context must not have a term definition for value that is a property generator. Otherwise, an invalid error has been detected, which is an error.
      if local_context && term_definitions[value] && term_definitions[value].property_generator?
        raise InvalidContext::Syntax, "can't expand a context term which is a property generator"
      end

      # If value has a null mapping in active context, then explicitly ignore value by returning null.
      if term_definitions.has_key?(value) && term_definitions[value].nil?
        return nil
      end

      # If active context indicates that value is a keyword alias then return the associated keyword.
      if kwa = keyword_aliases.keys.detect {|k| keyword_aliases[k].include?(value)}
        return kwa
      end

      result, isAbsoluteIri = value, false

      # If active context has a term definition for value, then set result to the associated IRI mapping and isAbsoluteIri to true.
      if td = term_definitions[value]
        debug("expand_iri") {"match: #{value.inspect} to #{td.id}"} unless options[:quiet]
        result, isAbsoluteIri = td.id, true
      end

      # If isAbsoluteIri equals false and result contains a colon (:), then it is either an absolute IRI or a compact IRI:
      if !isAbsoluteIri && value.include?(':')
        prefix, suffix = value.split(':', 2)
        debug("expand_iri") {"prefix: #{prefix.inspect}, suffix: #{suffix.inspect}, vocab: #{vocab.inspect}"} unless options[:quiet]

        # If prefix does not equal underscore (_) and suffix does not begin with double-forward-slash (//), then it may be a compact IRI:
        if prefix != '_' && suffix[0,2] != '//'
          # If local context is not null, it contains a key that equals prefix, and the value associated with the key that equals prefix in defined is not true, then invoke the Create Term Definition subalgorithm, passing active context, local context, prefix as term, and defined. This will ensure that a term definition is created for prefix in active context during Context Processing.
          create_term_definition(local_context, prefix, defined) if local_context && defined[prefix]

          # If active context contains a term definition for prefix that is not a property generator then set result to the result of concatenating the value associated with the prefix's IRI mapping and suffix.
          result = td.id + suffix if (td = term_definitions[prefix]) && !td.property_generator?
        end
        isAbsoluteIri = true
      end
      debug("expand_iri") {"result: #{result.inspect}, abs: #{isAbsoluteIri.inspect}"} unless options[:quiet]

      result = if isAbsoluteIri
        # If local context equals null and result begins with and underscore and colon (_:) then result is a blank node identifier. Set result to the result of the Generate Blank Node Identifier algorithm, passing active context and result for identifier.
        result[0,2] == '_:' ? namer.get_name(result) : result
      elsif options[:vocabRelative] && vocab
        # Otherwise, if vocabRelative equals true and active context has a vocabulary mapping, then set result to the result of concatenating the vocabulary mapping with result.
        vocab + result
      elsif options[:documentRelative] && base = options.fetch(:base, self.base)
        # Otherwise, if documentRelative equals true, set result to the result of resolving result against the document base as per [RFC3986]
        RDF::URI(base).join(result).to_s
      else
        result
      end
      debug(" =>") {result} unless options[:quiet]

      # If local context is not null then result must be an absolute IRI. Otherwise, an invalid context value has been detected, which is an error. Return result.
      unless result.include?(':') || KEYWORDS.include?(result)
        raise InvalidContext::Syntax, "Expected #{value.inspect} to be absolute" if options[:validate]
        result = nil
      end
      result
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
        if list?(value) && !index?(value)
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
        # Don't use vocab, if the result would collide with a term
        if vocab && terms.empty? && iri.to_s.index(vocab) == 0 &&
          !mapping(iri.to_s.sub(vocab, '')) &&
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

        value = if value.is_a?(RDF::Value)
          value
        elsif coerce(property) == '@id'
          expand_iri(value, :documentRelative => true)
        else
          RDF::Literal(value)
        end
        debug("expand_value") {"normalized: #{value.inspect}"}
        
        result = case value
        when RDF::URI, RDF::Node
          debug("URI | BNode") { value.to_s }
          {'@id' => value.to_s}
        when RDF::Literal
          debug("Literal") {"datatype: #{value.datatype.inspect}"}
          res = Hash.ordered
          if options[:useNativeTypes] && [RDF::XSD.boolean, RDF::XSD.integer, RDF::XSD.double].include?(value.datatype)
            res['@value'] = value.object
            res['@type'] = uri(coerce(property)) if coerce(property)
          else
            value.canonicalize! if value.datatype == RDF::XSD.double
            res['@value'] = value.to_s
            if coerce(property)
              res['@type'] = uri(coerce(property)).to_s
            elsif value.has_datatype?
              res['@type'] = uri(value.datatype).to_s
            elsif value.has_language? || language(property)
              res['@language'] = (value.language || language(property)).to_s
            end
          end
          res
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

        # Remove @index if property has annotation
        value.delete('@index') if container(property) == '@index'

        result = case
        when value.has_key?('@index')
          # Don't compact the value
          debug {" (@index without container @index)"}
          value
        when coerce(property) == '@id' && value.has_key?('@id')
          # Compact an @id coercion
          debug {" (@id & coerce)"}
          compact_iri(value['@id'], :position => :subject)
        when value['@type'] && expand_iri(value['@type'], :vocabRelative => true) == coerce(property)
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
        when !value.fetch('@value', "").is_a?(String)
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
      v = %w([Context)
      v << "vocab=#{vocab}"
      v << "def_language=#{default_language}"
      v << "term_definitions[#{term_definitions.length}]=#{term_definitions}"
      v.join(", ") + "]"
    end
    
    def dup
      # Also duplicate mappings, coerce and list
      that = self
      ec = super
      ec.instance_eval do
        @vocab = that.vocab
        @namer = that.namer
        @default_language = that.default_language
        @keyword_aliases = that.keyword_aliases.dup
        @term_definitions = that.term_definitions.dup
        @options = that.options
        @iri_to_term = that.iri_to_term.dup
      end
      ec
    end

    private

    def uri(value)
      case value.to_s
      when /^_:(.*)$/
        # Map BlankNodes if a namer is given
        debug "uri(bnode)#{value}: #{$1}"
        bnode(namer.get_sym($1))
      else
        value = RDF::URI.new(value)
        value.validate! if @options[:validate]
        value.canonicalize! if @options[:canonicalize]
        value = RDF::URI.intern(value) if @options[:intern]
        value
      end
    end

    # Clear the provided context, used for testing
    # @return [Context] self
    def clear_provided_context
      provided_context = nil
      self
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
          debug("term rank") { "empty list"}
          container(term) == '@list' ? 1 : 0
        else
          debug("term rank") { "non-empty list"}
          # Otherwise, return the most specific term, for which the term has some match against every value.
          depth {value['@list'].map {|v| term_rank(term, v)}}.min
        end
      elsif value?(value)
        val_type = value.fetch('@type', nil)
        val_lang = value['@language'] || false if value.has_key?('@language')
        debug("term rank") {"@val_type: #{val_type.inspect}, val_lang: #{val_lang.inspect}"}
        if val_type
          debug("term rank") { "typed value"}
          coerce(term) == val_type ? 3 :  (default_term ? 1 : 0)
        elsif !value['@value'].is_a?(String)
          debug("term rank") { "native value"}
          default_term ? 2 : 1
        elsif val_lang.nil?
          debug("val_lang.nil") {"#{language(term).inspect} && #{coerce(term).inspect}"}
          if language(term) == false || (default_term && default_language.nil?)
            # Value has no language, and there is no default language and the term has no language
            3
          elsif default_term
            # The term has no language (or type), but it's different than the default
            2
          else
            0
          end
        else
          debug("val_lang") {"#{language(term).inspect} && #{coerce(term).inspect}"}
          if val_lang && container(term) == '@language'
            3
          elsif val_lang == language(term) || (default_term && default_language == val_lang)
            2
          elsif default_term && container(term) == '@set'
            2 # Choose a set term before a non-set term, if there's a language
          elsif default_term
            1
          else
            0
          end
        end
      else # node definition/reference
        debug("node dev/ref")
        coerce(term) == '@id' ? 3 : (default_term ? 1 : 0)
      end
      
      debug(" =>") {rank.inspect}
      rank
    end
  end
end
