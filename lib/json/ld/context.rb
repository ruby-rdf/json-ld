# frozen_string_literal: true

require 'json'
require 'bigdecimal'
require 'set'
require 'rdf/util/cache'

module JSON
  module LD
    class Context
      include Utils
      include RDF::Util::Logger

      ##
      # Preloaded contexts.
      # To avoid runtime context parsing and downloading, contexts may be pre-loaded by implementations.
      # @return [Hash{Symbol => Context}]
      PRELOADED = {}

      # Initial contexts, defined on first access
      INITIAL_CONTEXTS = {}

      ##
      # Defines the maximum number of interned URI references that can be held
      # cached in memory at any one time.
      CACHE_SIZE = 100 # unlimited by default

      class << self
        ##
        # Add preloaded context. In the block form, the context is lazy evaulated on first use.
        # @param [String, RDF::URI] url
        # @param [Context] context (nil)
        # @yieldreturn [Context]
        def add_preloaded(url, context = nil, &block)
          PRELOADED[url.to_s.freeze] = context || block
        end

        ##
        # Alias a previousliy loaded context
        # @param [String, RDF::URI] a
        # @param [String, RDF::URI] url
        def alias_preloaded(a, url)
          PRELOADED[a.to_s.freeze] = PRELOADED[url.to_s.freeze]
        end
      end

      begin
        # Attempt to load this to avoid unnecessary context fetches
        require 'json/ld/preloaded'
      rescue LoadError
        # Silently allow this to fail
      end

      # The base.
      #
      # @return [RDF::URI] Current base IRI, used for expanding relative IRIs.
      attr_reader :base

      # @return [RDF::URI] base IRI of the context, if loaded remotely.
      attr_accessor :context_base

      # Term definitions
      # @return [Hash{String => TermDefinition}]
      attr_reader :term_definitions

      # @return [Hash{RDF::URI => String}] Reverse mappings from IRI to term only for terms, not CURIEs XXX
      attr_accessor :iri_to_term

      # Previous definition for this context. This is used for rolling back type-scoped contexts.
      # @return [Context]
      attr_accessor :previous_context

      # Context is property-scoped
      # @return [Boolean]
      attr_accessor :property_scoped

      # Default language
      #
      # This adds a language to plain strings that aren't otherwise coerced
      # @return [String]
      attr_reader :default_language

      # Default direction
      #
      # This adds a direction to plain strings that aren't otherwise coerced
      # @return ["lrt", "rtl"]
      attr_reader :default_direction

      # Default vocabulary
      #
      # Sets the default vocabulary used for expanding terms which
      # aren't otherwise absolute IRIs
      # @return [RDF::URI]
      attr_reader :vocab

      # @return [Hash{Symbol => Object}] Global options used in generating IRIs
      attr_accessor :options

      # @return [BlankNodeNamer]
      attr_accessor :namer

      ##
      # Create a new context by parsing a context.
      #
      # @see #initialize
      # @see #parse
      # @param [String, #read, Array, Hash, Context] local_context
      # @param [String, #to_s] base (nil)
      #   The Base IRI to use when expanding the document. This overrides the value of `input` if it is a _IRI_. If not specified and `input` is not an _IRI_, the base IRI defaults to the current document IRI if in a browser context, or the empty string if there is no document context.
      # @param [Boolean] override_protected (false)
      #   Protected terms may be cleared.
      # @param [Boolean] propagate (true)
      #   If false, retains any previously defined term, which can be rolled back when the descending into a new node object changes.
      # @raise [JsonLdError]
      #   on a remote context load error, syntax error, or a reference to a term which is not defined.
      # @return [Context]
      def self.parse(local_context,
                     base: nil,
                     override_protected: false,
                     propagate: true,
                     **options)
        c = new(**options)
        if local_context.respond_to?(:empty?) && local_context.empty?
          c
        else
          c.parse(local_context,
            base: base,
            override_protected: override_protected,
            propagate: propagate)
        end
      end

      ##
      # Class-level cache used for retaining parsed remote contexts.
      #
      # @return [RDF::Util::Cache]
      # @private
      def self.cache
        @cache ||= RDF::Util::Cache.new(CACHE_SIZE)
      end

      ##
      # Class-level cache inverse contexts.
      #
      # @return [RDF::Util::Cache]
      # @private
      def self.inverse_cache
        @inverse_cache ||= RDF::Util::Cache.new(CACHE_SIZE)
      end

      ##
      # @private
      # Allow caching of well-known contexts
      def self.new(**options)
        if (options.keys - %i[
          compactArrays
          documentLoader
          extractAllScripts
          ordered
          processingMode
          validate
        ]).empty?
          # allow caching
          key = options.hash
          INITIAL_CONTEXTS[key] ||= begin
            context = JSON::LD::Context.allocate
            context.send(:initialize, **options)
            context.freeze
            context.term_definitions.freeze
            context
          end
        else
          # Don't try to cache
          context = JSON::LD::Context.allocate
          context.send(:initialize, **options)
          context
        end
      end

      ##
      # Create new evaluation context
      # @param [Hash] options
      # @option options [Hash{Symbol => String}] :prefixes
      #   See `RDF::Reader#initialize`
      # @option options [String, #to_s] :vocab
      #   Initial value for @vocab
      # @option options [String, #to_s] :language
      #   Initial value for @langauge
      # @yield [ec]
      # @yieldparam [Context]
      # @return [Context]
      def initialize(**options)
        @processingMode = 'json-ld-1.0' if options[:processingMode] == 'json-ld-1.0'
        @term_definitions = {}
        @iri_to_term = {
          RDF.to_uri.to_s => "rdf",
          RDF::XSD.to_uri.to_s => "xsd"
        }
        @namer = BlankNodeMapper.new("t")

        @options = options

        # Load any defined prefixes
        (options[:prefixes] || {}).each_pair do |k, v|
          next if k.nil?

          @iri_to_term[v.to_s] = k
          @term_definitions[k.to_s] = TermDefinition.new(k, id: v.to_s, simple: true, prefix: true)
        end

        self.vocab = options[:vocab] if options[:vocab]
        self.default_language = options[:language] if /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(options[:language])
        @term_definitions = options[:term_definitions] if options[:term_definitions]

        # log_debug("init") {"iri_to_term: #{iri_to_term.inspect}"}

        yield(self) if block_given?
      end

      # Create an Evaluation Context
      #
      # When processing a JSON-LD data structure, each processing rule is applied using information provided by the active context. This section describes how to produce an active context.
      #
      # The active context contains the active term definitions which specify how properties and values have to be interpreted as well as the current base IRI, the vocabulary mapping and the default language. Each term definition consists of an IRI mapping, a boolean flag reverse property, an optional type mapping or language mapping, and an optional container mapping. A term definition can not only be used to map a term to an IRI, but also to map a term to a keyword, in which case it is referred to as a keyword alias.
      #
      # When processing, the active context is initialized without any term definitions, vocabulary mapping, or default language. If a local context is encountered during processing, a new active context is created by cloning the existing active context. Then the information from the local context is merged into the new active context. Given that local contexts may contain references to remote contexts, this includes their retrieval.
      #
      #
      # @param [String, #read, Array, Hash, Context] local_context
      # @param [String, #to_s] base
      #   The Base IRI to use when expanding the document. This overrides the value of `input` if it is a _IRI_. If not specified and `input` is not an _IRI_, the base IRI defaults to the current document IRI if in a browser context, or the empty string if there is no document context.
      # @param [Boolean] override_protected Protected terms may be cleared.
      # @param [Boolean] propagate (true)
      #   If false, retains any previously defined term, which can be rolled back when the descending into a new node object changes.
      # @param [Array<String>] remote_contexts ([])
      # @param [Boolean] validate_scoped (true).
      #   Validate scoped context, loading if necessary.
      #   If false, do not load scoped contexts.
      # @raise [JsonLdError]
      #   on a remote context load error, syntax error, or a reference to a term which is not defined.
      # @return [Context]
      # @see https://www.w3.org/TR/json-ld11-api/index.html#context-processing-algorithm
      def parse(local_context,
                base: nil,
                override_protected: false,
                propagate: true,
                remote_contexts: [],
                validate_scoped: true)
        result = dup
        # Early check for @propagate, which can only appear in a local context
        propagate = local_context.is_a?(Hash) ? local_context.fetch('@propagate', propagate) : propagate
        result.previous_context ||= result.dup unless propagate

        local_context = as_array(local_context)

        log_depth do
          local_context.each do |context|
            case context
            when nil, false
              # 3.1 If the `override_protected` is  false, and the active context contains protected terms, an error is raised.
              if override_protected || result.term_definitions.values.none?(&:protected?)
                null_context = Context.new(**options)
                null_context.previous_context = result unless propagate
                result = null_context
              else
                raise JSON::LD::JsonLdError::InvalidContextNullification,
                  "Attempt to clear a context with protected terms"
              end
            when Context
              # log_debug("parse") {"context: #{context.inspect}"}
              result = result.merge(context)
            when IO, StringIO
              # log_debug("parse") {"io: #{context}"}
              # Load context document, if it is an open file
              begin
                ctx = load_context(context, **@options)
                if @options[:validate] && ctx['@context'].nil?
                  raise JSON::LD::JsonLdError::InvalidRemoteContext,
                    "Context missing @context key"
                end

                result = result.parse(ctx["@context"] || {})
              rescue JSON::ParserError => e
                log_info("parse") { "Failed to parse @context from remote document at #{context}: #{e.message}" }
                if @options[:validate]
                  raise JSON::LD::JsonLdError::InvalidRemoteContext,
                    "Failed to parse remote context at #{context}: #{e.message}"
                end

                self
              end
            when String, RDF::URI
              # log_debug("parse") {"remote: #{context}, base: #{result.context_base || result.base}"}

              # 3.2.1) Set context to the result of resolving value against the base IRI which is established as specified in section 5.1 Establishing a Base URI of [RFC3986]. Only the basic algorithm in section 5.2 of [RFC3986] is used; neither Syntax-Based Normalization nor Scheme-Based Normalization are performed. Characters additionally allowed in IRI references are treated in the same way that unreserved characters are treated in URI references, per section 6.5 of [RFC3987].
              context = RDF::URI(result.context_base || base).join(context)
              context_canon = context.canonicalize
              context_canon.scheme = 'http' if context_canon.scheme == 'https'

              # If validating a scoped context which has already been loaded, skip to the next one
              next if !validate_scoped && remote_contexts.include?(context.to_s)

              remote_contexts << context.to_s
              raise JsonLdError::ContextOverflow, context.to_s if remote_contexts.length >= MAX_CONTEXTS_LOADED

              cached_context = if PRELOADED[context_canon.to_s]
                # If we have a cached context, merge it into the current context (result) and use as the new context
                # log_debug("parse") {"=> cached_context: #{context_canon.to_s.inspect}"}

                # If this is a Proc, then replace the entry with the result of running the Proc
                if PRELOADED[context_canon.to_s].respond_to?(:call)
                  # log_debug("parse") {"=> (call)"}
                  PRELOADED[context_canon.to_s] = PRELOADED[context_canon.to_s].call
                end
                PRELOADED[context_canon.to_s].context_base ||= context_canon.to_s
                PRELOADED[context_canon.to_s]
              else
                # Load context document, if it is a string
                Context.cache[context_canon.to_s] ||= begin
                  context_opts = @options.merge(
                    profile: 'http://www.w3.org/ns/json-ld#context',
                    requestProfile: 'http://www.w3.org/ns/json-ld#context',
                    base: nil
                  )
                  # context_opts.delete(:headers)
                  JSON::LD::API.loadRemoteDocument(context.to_s, **context_opts) do |remote_doc|
                    # 3.2.5) Dereference context. If the dereferenced document has no top-level JSON object with an @context member, an invalid remote context has been detected and processing is aborted; otherwise, set context to the value of that member.
                    unless remote_doc.document.is_a?(Hash) && remote_doc.document.key?('@context')
                      raise JsonLdError::InvalidRemoteContext,
                        context.to_s
                    end

                    # Parse stand-alone
                    ctx = Context.new(unfrozen: true, **options).dup
                    ctx.context_base = context.to_s
                    ctx = ctx.parse(remote_doc.document['@context'], remote_contexts: remote_contexts.dup)
                    ctx.context_base = context.to_s # In case it was altered
                    ctx.instance_variable_set(:@base, nil)
                    ctx
                  end
                rescue JsonLdError::LoadingDocumentFailed => e
                  log_info("parse") do
                    "Failed to retrieve @context from remote document at #{context_canon.inspect}: #{e.message}"
                  end
                  raise JsonLdError::LoadingRemoteContextFailed, "#{context}: #{e.message}", e.backtrace
                rescue JsonLdError
                  raise
                rescue StandardError => e
                  log_info("parse") do
                    "Failed to retrieve @context from remote document at #{context_canon.inspect}: #{e.message}"
                  end
                  raise JsonLdError::LoadingRemoteContextFailed, "#{context}: #{e.message}", e.backtrace
                end
              end

              # Merge loaded context noting protected term overriding
              context = result.merge(cached_context, override_protected: override_protected)

              context.previous_context = self unless propagate
              result = context
            when Hash
              context = context.dup # keep from modifying a hash passed as a param

              # This counts on hash elements being processed in order
              {
                '@version' => :processingMode=,
                '@import' => nil,
                '@base' => :base=,
                '@direction' => :default_direction=,
                '@language' => :default_language=,
                '@propagate' => :propagate=,
                '@vocab' => :vocab=
              }.each do |key, setter|
                next unless context.key?(key)

                if key == '@import'
                  # Retrieve remote context and merge the remaining context object into the result.
                  if result.processingMode("json-ld-1.0")
                    raise JsonLdError::InvalidContextEntry,
                      "@import may only be used in 1.1 mode}"
                  end
                  unless context['@import'].is_a?(String)
                    raise JsonLdError::InvalidImportValue,
                      "@import must be a string: #{context['@import'].inspect}"
                  end

                  import_loc = RDF::URI(result.context_base || base).join(context['@import'])
                  begin
                    context_opts = @options.merge(
                      profile: 'http://www.w3.org/ns/json-ld#context',
                      requestProfile: 'http://www.w3.org/ns/json-ld#context',
                      base: nil
                    )
                    context_opts.delete(:headers)
                    # FIXME: should cache this, but ContextCache is for parsed contexts
                    JSON::LD::API.loadRemoteDocument(import_loc, **context_opts) do |remote_doc|
                      # Dereference import_loc. If the dereferenced document has no top-level JSON object with an @context member, an invalid remote context has been detected and processing is aborted; otherwise, set context to the value of that member.
                      unless remote_doc.document.is_a?(Hash) && remote_doc.document.key?('@context')
                        raise JsonLdError::InvalidRemoteContext,
                          import_loc.to_s
                      end

                      import_context = remote_doc.document['@context']
                      import_context.delete('@base')
                      unless import_context.is_a?(Hash)
                        raise JsonLdError::InvalidRemoteContext,
                          "#{import_context.to_json} must be an object"
                      end
                      if import_context.key?('@import')
                        raise JsonLdError::InvalidContextEntry,
                          "#{import_context.to_json} must not include @import entry"
                      end

                      context.delete(key)
                      context = import_context.merge(context)
                    end
                  rescue JsonLdError::LoadingDocumentFailed => e
                    raise JsonLdError::LoadingRemoteContextFailed, "#{import_loc}: #{e.message}", e.backtrace
                  rescue JsonLdError
                    raise
                  rescue StandardError => e
                    raise JsonLdError::LoadingRemoteContextFailed, "#{import_loc}: #{e.message}", e.backtrace
                  end
                else
                  result.send(setter, context[key], remote_contexts: remote_contexts)
                end
                context.delete(key)
              end

              defined = {}

              # For each key-value pair in context invoke the Create Term Definition subalgorithm, passing result for active context, context for local context, key, and defined
              context.each_key do |key|
                # ... where key is not @base, @vocab, @language, or @version
                next if NON_TERMDEF_KEYS.include?(key)

                result.create_term_definition(context, key, defined,
                  base: base,
                  override_protected: override_protected,
                  protected: context['@protected'],
                  remote_contexts: remote_contexts.dup,
                  validate_scoped: validate_scoped)
              end
            else
              # 3.3) If context is not a JSON object, an invalid local context error has been detected and processing is aborted.
              raise JsonLdError::InvalidLocalContext, "must be a URL, JSON object or array of same: #{context.inspect}"
            end
          end
        end
        result
      end

      ##
      # Merge in a context, creating a new context with updates from `context`
      #
      # @param [Context] context
      # @param [Boolean] override_protected Allow or disallow protected terms to be changed
      # @return [Context]
      def merge(context, override_protected: false)
        ctx = Context.new(term_definitions: term_definitions, standard_prefixes: options[:standard_prefixes])
        ctx.context_base = context.context_base || context_base
        ctx.default_language = context.default_language || default_language
        ctx.default_direction = context.default_direction || default_direction
        ctx.vocab = context.vocab || vocab
        ctx.base = base unless base.nil?
        unless override_protected
          ctx.term_definitions.each do |term, definition|
            next unless definition.protected? && (other = context.term_definitions[term])
            unless definition == other
              raise JSON::LD::JsonLdError::ProtectedTermRedefinition, "Attempt to redefine protected term #{term}"
            end
          end
        end

        # Add term definitions
        context.term_definitions.each do |term, definition|
          ctx.term_definitions[term] = definition
        end
        ctx
      end

      # The following constants are used to reduce object allocations in #create_term_definition below
      ID_NULL_OBJECT = { '@id' => nil }.freeze
      NON_TERMDEF_KEYS = Set.new(%w[@base @direction @language @protected @version @vocab]).freeze
      JSON_LD_10_EXPECTED_KEYS = Set.new(%w[@container @id @language @reverse @type]).freeze
      JSON_LD_11_EXPECTED_KEYS = Set.new(%w[@context @direction @index @nest @prefix @protected]).freeze
      JSON_LD_EXPECTED_KEYS = (JSON_LD_10_EXPECTED_KEYS + JSON_LD_11_EXPECTED_KEYS).freeze
      JSON_LD_10_TYPE_VALUES = Set.new(%w[@id @vocab]).freeze
      JSON_LD_11_TYPE_VALUES = Set.new(%w[@json @none]).freeze
      PREFIX_URI_ENDINGS = Set.new(%w(: / ? # [ ] @)).freeze

      ##
      # Create Term Definition
      #
      # Term definitions are created by parsing the information in the given local context for the given term. If the given term is a compact IRI, it may omit an IRI mapping by depending on its prefix having its own term definition. If the prefix is a key in the local context, then its term definition must first be created, through recursion, before continuing. Because a term definition can depend on other term definitions, a mechanism must be used to detect cyclical dependencies. The solution employed here uses a map, defined, that keeps track of whether or not a term has been defined or is currently in the process of being defined. This map is checked before any recursion is attempted.
      #
      # After all dependencies for a term have been defined, the rest of the information in the local context for the given term is taken into account, creating the appropriate IRI mapping, container mapping, and type mapping or language mapping for the term.
      #
      # @param [Hash] local_context
      # @param [String] term
      # @param [Hash] defined
      # @param [String, RDF::URI] base for resolving document-relative IRIs
      # @param [Boolean] protected if true, causes all terms to be marked protected
      # @param [Boolean] override_protected Protected terms may be cleared.
      # @param [Array<String>] remote_contexts
      # @param [Boolean] validate_scoped (true).
      #   Validate scoped context, loading if necessary.
      #   If false, do not load scoped contexts.
      # @raise [JsonLdError]
      #   Represents a cyclical term dependency
      # @see https://www.w3.org/TR/json-ld11-api/index.html#create-term-definition
      def create_term_definition(local_context, term, defined,
                                 base: nil,
                                 override_protected: false,
                                 protected: nil,
                                 remote_contexts: [],
                                 validate_scoped: true)
        # Expand a string value, unless it matches a keyword
        # log_debug("create_term_definition") {"term = #{term.inspect}"}

        # If defined contains the key term, then the associated value must be true, indicating that the term definition has already been created, so return. Otherwise, a cyclical term definition has been detected, which is an error.
        case defined[term]
        when TrueClass then return
        when nil
          defined[term] = false
        else
          raise JsonLdError::CyclicIRIMapping, "Cyclical term dependency found: #{term.inspect}"
        end

        # Initialize value to a the value associated with the key term in local context.
        value = local_context.fetch(term, false)
        simple_term = value.is_a?(String) || value.nil?

        # Since keywords cannot be overridden, term must not be a keyword. Otherwise, an invalid value has been detected, which is an error.
        if term == '@type' &&
           value.is_a?(Hash) &&
           !value.empty? &&
           processingMode("json-ld-1.1") &&
           (value.keys - %w[@container @protected]).empty? &&
           value.fetch('@container', '@set') == '@set'
          # thes are the only cases were redefining a keyword is allowed
        elsif KEYWORDS.include?(term) # TODO: anything that looks like a keyword
          raise JsonLdError::KeywordRedefinition, "term must not be a keyword: #{term.inspect}" if
            @options[:validate]
        elsif term.to_s.match?(/^@[a-zA-Z]+$/) && @options[:validate]
          warn "Terms beginning with '@' are reserved for future use and ignored: #{term}."
          return
        elsif !term_valid?(term) && @options[:validate]
          raise JsonLdError::InvalidTermDefinition, "term is invalid: #{term.inspect}"
        end

        value = { '@id' => value } if simple_term

        # Remove any existing term definition for term in active context.
        previous_definition = term_definitions[term]
        if previous_definition&.protected? && !override_protected
          # Check later to detect identical redefinition
        elsif previous_definition
          term_definitions.delete(term)
        end

        unless value.is_a?(Hash)
          raise JsonLdError::InvalidTermDefinition,
            "Term definition for #{term.inspect} is an #{value.class} on term #{term.inspect}"
        end

        # log_debug("") {"Hash[#{term.inspect}] = #{value.inspect}"}
        definition = TermDefinition.new(term)
        definition.simple = simple_term

        expected_keys = case processingMode
        when "json-ld-1.0" then JSON_LD_10_EXPECTED_KEYS
        else JSON_LD_EXPECTED_KEYS
        end

        # Any of these keys cause us to process as json-ld-1.1, unless otherwise set
        if processingMode.nil? && value.any? { |key, _| !JSON_LD_11_EXPECTED_KEYS.include?(key) }
          processingMode('json-ld-11')
        end

        if value.any? { |key, _| !expected_keys.include?(key) }
          extra_keys = value.keys - expected_keys.to_a
          raise JsonLdError::InvalidTermDefinition,
            "Term definition for #{term.inspect} has unexpected keys: #{extra_keys.join(', ')}"
        end

        # Potentially note that the term is protected
        definition.protected = value.fetch('@protected', protected)

        if value.key?('@type')
          type = value['@type']
          # SPEC FIXME: @type may be nil
          type = case type
          when nil
            type
          when String
            begin
              expand_iri(type, vocab: true, documentRelative: false, local_context: local_context, defined: defined)
            rescue JsonLdError::InvalidIRIMapping
              raise JsonLdError::InvalidTypeMapping,
                "invalid mapping for '@type': #{type.inspect} on term #{term.inspect}"
            end
          else
            :error
          end
          if JSON_LD_11_TYPE_VALUES.include?(type) && processingMode('json-ld-1.1')
            # This is okay and used in compaction in 1.1
          elsif !JSON_LD_10_TYPE_VALUES.include?(type) && !(type.is_a?(RDF::URI) && type.absolute?)
            raise JsonLdError::InvalidTypeMapping,
              "unknown mapping for '@type': #{type.inspect} on term #{term.inspect}"
          end
          # log_debug("") {"type_mapping: #{type.inspect}"}
          definition.type_mapping = type
        end

        if value.key?('@reverse')
          raise JsonLdError::InvalidReverseProperty, "unexpected key in #{value.inspect} on term #{term.inspect}" if
            value.key?('@id') || value.key?('@nest')

          unless value['@reverse'].is_a?(String)
            raise JsonLdError::InvalidIRIMapping,
              "expected value of @reverse to be a string: #{value['@reverse'].inspect} on term #{term.inspect}"
          end

          if value['@reverse'].to_s.match?(/^@[a-zA-Z]+$/) && @options[:validate]
            warn "Values beginning with '@' are reserved for future use and ignored: #{value['@reverse']}."
            return
          end

          # Otherwise, set the IRI mapping of definition to the result of using the IRI Expansion algorithm, passing active context, the value associated with the @reverse key for value, true for vocab, true for document relative, local context, and defined. If the result is not an absolute IRI, i.e., it contains no colon (:), an invalid IRI mapping error has been detected and processing is aborted.
          definition.id = expand_iri(value['@reverse'],
            vocab: true,
            local_context: local_context,
            defined: defined)
          unless definition.id.is_a?(RDF::Node) || (definition.id.is_a?(RDF::URI) && definition.id.absolute?)
            raise JsonLdError::InvalidIRIMapping,
              "non-absolute @reverse IRI: #{definition.id} on term #{term.inspect}"
          end

          if term[1..].to_s.include?(':') && (term_iri = expand_iri(term)) != definition.id
            raise JsonLdError::InvalidIRIMapping, "term #{term} expands to #{definition.id}, not #{term_iri}"
          end

          if @options[:validate] && processingMode('json-ld-1.1') && definition.id.to_s.start_with?("_:")
            warn "[DEPRECATION] Blank Node terms deprecated in JSON-LD 1.1."
          end

          # If value contains an @container member, set the container mapping of definition to its value; if its value is neither @set, @index, @type, @id, an absolute IRI nor null, an invalid reverse property error has been detected (reverse properties only support set- and index-containers) and processing is aborted.
          if value.key?('@container')
            container = value['@container']
            unless container.is_a?(String) && ['@set', '@index'].include?(container)
              raise JsonLdError::InvalidReverseProperty,
                "unknown mapping for '@container' to #{container.inspect} on term #{term.inspect}"
            end
            definition.container_mapping = check_container(container, local_context, defined, term)
          end
          definition.reverse_property = true
        elsif value.key?('@id') && value['@id'].nil?
          # Allowed to reserve a null term, which may be protected
        elsif value.key?('@id') && value['@id'] != term
          unless value['@id'].is_a?(String)
            raise JsonLdError::InvalidIRIMapping,
              "expected value of @id to be a string: #{value['@id'].inspect} on term #{term.inspect}"
          end

          if !KEYWORDS.include?(value['@id'].to_s) && value['@id'].to_s.match?(/^@[a-zA-Z]+$/) && @options[:validate]
            warn "Values beginning with '@' are reserved for future use and ignored: #{value['@id']}."
            return
          end

          definition.id = expand_iri(value['@id'],
            vocab: true,
            local_context: local_context,
            defined: defined)
          raise JsonLdError::InvalidKeywordAlias, "expected value of @id to not be @context on term #{term.inspect}" if
            definition.id == '@context'

          if term.match?(%r{(?::[^:])|/})
            term_iri = expand_iri(term,
              vocab: true,
              local_context: local_context,
              defined: defined.merge(term => true))
            if term_iri != definition.id
              raise JsonLdError::InvalidIRIMapping, "term #{term} expands to #{definition.id}, not #{term_iri}"
            end
          end

          if @options[:validate] && processingMode('json-ld-1.1') && definition.id.to_s.start_with?("_:")
            warn "[DEPRECATION] Blank Node terms deprecated in JSON-LD 1.1."
          end

          # If id ends with a gen-delim, it may be used as a prefix for simple terms
          definition.prefix = true if !term.include?(':') &&
                                      simple_term &&
                                      (definition.id.to_s.end_with?(':', '/', '?', '#', '[', ']',
                                        '@') || definition.id.to_s.start_with?('_:'))
        elsif term[1..].include?(':')
          # If term is a compact IRI with a prefix that is a key in local context then a dependency has been found. Use this algorithm recursively passing active context, local context, the prefix as term, and defined.
          prefix, suffix = term.split(':', 2)
          create_term_definition(local_context, prefix, defined, protected: protected) if local_context.key?(prefix)

          definition.id = if (td = term_definitions[prefix])
            # If term's prefix has a term definition in active context, set the IRI mapping for definition to the result of concatenating the value associated with the prefix's IRI mapping and the term's suffix.
            td.id + suffix
          else
            # Otherwise, term is an absolute IRI. Set the IRI mapping for definition to term
            term
          end
          # log_debug("") {"=> #{definition.id}"}
        elsif term.include?('/')
          # If term is a relative IRI
          definition.id = expand_iri(term, vocab: true)
          raise JsonLdError::InvalidKeywordAlias, "expected term to expand to an absolute IRI #{term.inspect}" unless
            definition.id.absolute?
        elsif KEYWORDS.include?(term)
          # This should only happen for @type when @container is @set
          definition.id = term
        else
          # Otherwise, active context must have a vocabulary mapping, otherwise an invalid value has been detected, which is an error. Set the IRI mapping for definition to the result of concatenating the value associated with the vocabulary mapping and term.
          unless vocab
            raise JsonLdError::InvalidIRIMapping,
              "relative term definition without vocab: #{term} on term #{term.inspect}"
          end

          definition.id = vocab + term
          # log_debug("") {"=> #{definition.id}"}
        end

        @iri_to_term[definition.id] = term if simple_term && definition.id

        if value.key?('@container')
          # log_debug("") {"container_mapping: #{value['@container'].inspect}"}
          definition.container_mapping = check_container(value['@container'], local_context, defined, term)

          # If @container includes @type
          if definition.container_mapping.include?('@type')
            # If definition does not have @type, set @type to @id
            definition.type_mapping ||= '@id'
            # If definition includes @type with a value other than @id or @vocab, an illegal type mapping error has been detected
            unless CONTEXT_TYPE_ID_VOCAB.include?(definition.type_mapping)
              raise JsonLdError::InvalidTypeMapping, "@container: @type requires @type to be @id or @vocab"
            end
          end
        end

        if value.key?('@index')
          # property-based indexing
          unless definition.container_mapping.include?('@index')
            raise JsonLdError::InvalidTermDefinition,
              "@index without @index in @container: #{value['@index']} on term #{term.inspect}"
          end
          unless value['@index'].is_a?(String) && !value['@index'].start_with?('@')
            raise JsonLdError::InvalidTermDefinition,
              "@index must expand to an IRI: #{value['@index']} on term #{term.inspect}"
          end

          definition.index = value['@index'].to_s
        end

        if value.key?('@context')
          begin
            new_ctx = parse(value['@context'],
              base: base,
              override_protected: true,
              remote_contexts: remote_contexts,
              validate_scoped: false)
            # Record null context in array form
            definition.context = case value['@context']
            when String then new_ctx.context_base
            when nil then [nil]
            else value['@context']
            end
            # log_debug("") {"context: #{definition.context.inspect}"}
          rescue JsonLdError => e
            raise JsonLdError::InvalidScopedContext,
              "Term definition for #{term.inspect} contains illegal value for @context: #{e.message}"
          end
        end

        if value.key?('@language')
          language = value['@language']
          language = case value['@language']
          when String
            # Warn on an invalid language tag, unless :validate is true, in which case it's an error
            unless /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(value['@language'])
              warn "@language must be valid BCP47: #{value['@language'].inspect}"
            end
            options[:lowercaseLanguage] ? value['@language'].downcase : value['@language']
          when nil
            nil
          else
            raise JsonLdError::InvalidLanguageMapping,
              "language must be null or a string, was #{value['@language'].inspect}} on term #{term.inspect}"
          end
          # log_debug("") {"language_mapping: #{language.inspect}"}
          definition.language_mapping = language || false
        end

        if value.key?('@direction')
          direction = value['@direction']
          unless direction.nil? || %w[
            ltr rtl
          ].include?(direction)
            raise JsonLdError::InvalidBaseDirection,
              "direction must be null, 'ltr', or 'rtl', was #{language.inspect}} on term #{term.inspect}"
          end

          # log_debug("") {"direction_mapping: #{direction.inspect}"}
          definition.direction_mapping = direction || false
        end

        if value.key?('@nest')
          nest = value['@nest']
          unless nest.is_a?(String)
            raise JsonLdError::InvalidNestValue,
              "nest must be a string, was #{nest.inspect}} on term #{term.inspect}"
          end
          if nest.match?(/^@[a-zA-Z]+$/) && nest != '@nest'
            raise JsonLdError::InvalidNestValue,
              "nest must not be a keyword other than @nest, was #{nest.inspect}} on term #{term.inspect}"
          end

          # log_debug("") {"nest: #{nest.inspect}"}
          definition.nest = nest
        end

        if value.key?('@prefix')
          if term.match?(%r{:|/})
            raise JsonLdError::InvalidTermDefinition,
              "@prefix used on compact or relative IRI term #{term.inspect}"
          end

          case pfx = value['@prefix']
          when TrueClass, FalseClass
            definition.prefix = pfx
          else
            raise JsonLdError::InvalidPrefixValue, "unknown value for '@prefix': #{pfx.inspect} on term #{term.inspect}"
          end

          if pfx && KEYWORDS.include?(definition.id.to_s)
            raise JsonLdError::InvalidTermDefinition,
              "keywords may not be used as prefixes"
          end
        end

        if !override_protected && previous_definition&.protected?
          if definition != previous_definition
            raise JSON::LD::JsonLdError::ProtectedTermRedefinition, "Attempt to redefine protected term #{term}"
          end
          definition = previous_definition
        end

        term_definitions[term] = definition
        defined[term] = true
      end

      ##
      # Initial context, without mappings, vocab or default language
      #
      # @return [Boolean]
      def empty?
        @term_definitions.empty? && vocab.nil? && default_language.nil?
      end

      # @param [String] value must be an absolute IRI
      def base=(value, **_options)
        if value
          unless value.is_a?(String) || value.is_a?(RDF::URI)
            raise JsonLdError::InvalidBaseIRI,
              "@base must be a string: #{value.inspect}"
          end

          value = RDF::URI(value)
          value = @base.join(value) if @base && value.relative?
          # still might be relative to document
          @base = value
        else
          @base = false
        end
      end

      # @param [String] value
      def default_language=(value, **options)
        @default_language = case value
        when String
          # Warn on an invalid language tag, unless :validate is true, in which case it's an error
          unless /^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$/.match?(value)
            warn "@language must be valid BCP47: #{value.inspect}"
          end
          options[:lowercaseLanguage] ? value.downcase : value
        when nil
          nil
        else
          raise JsonLdError::InvalidDefaultLanguage, "@language must be a string: #{value.inspect}"
        end
      end

      # @param [String] value
      def default_direction=(value, **_options)
        @default_direction = if value
          unless %w[
            ltr rtl
          ].include?(value)
            raise JsonLdError::InvalidBaseDirection,
              "@direction must be one or 'ltr', or 'rtl': #{value.inspect}"
          end

          value
        end
      end

      ##
      # Retrieve, or check processing mode.
      #
      # * With no arguments, retrieves the current set processingMode.
      # * With an argument, verifies that the processingMode is at least that provided, either as an integer, or a string of the form "json-ld-1.x"
      # * If expecting 1.1, and not set, it has the side-effect of setting mode to json-ld-1.1.
      #
      # @param [String, Number] expected (nil)
      # @return [String]
      def processingMode(expected = nil)
        case expected
        when 1.0, 'json-ld-1.0'
          @processingMode == 'json-ld-1.0'
        when 1.1, 'json-ld-1.1'
          @processingMode.nil? || @processingMode == 'json-ld-1.1'
        when nil
          @processingMode || 'json-ld-1.1'
        else
          false
        end
      end

      ##
      # Set processing mode.
      #
      # * With an argument, verifies that the processingMode is at least that provided, either as an integer, or a string of the form "json-ld-1.x"
      #
      # If contex has a @version member, it's value MUST be 1.1, otherwise an "invalid @version value" has been detected, and processing is aborted.
      # If processingMode has been set, and it is not "json-ld-1.1", a "processing mode conflict" has been detecting, and processing is aborted.
      #
      # @param [String, Number] value
      # @return [String]
      # @raise [JsonLdError::ProcessingModeConflict]
      def processingMode=(value = nil, **_options)
        value = "json-ld-1.1" if value == 1.1
        case value
        when "json-ld-1.0", "json-ld-1.1"
          if @processingMode && @processingMode != value
            raise JsonLdError::ProcessingModeConflict, "#{value} not compatible with #{@processingMode}"
          end

          @processingMode = value
        else
          raise JsonLdError::InvalidVersionValue, value.inspect
        end
      end

      # If context has a @vocab member: if its value is not a valid absolute IRI or null trigger an INVALID_VOCAB_MAPPING error; otherwise set the active context's vocabulary mapping to its value and remove the @vocab member from context.
      # @param [String] value must be an absolute IRI
      def vocab=(value, **_options)
        @vocab = case value
        when /_:/
          # BNode vocab is deprecated
          if @options[:validate] && processingMode("json-ld-1.1")
            warn "[DEPRECATION] Blank Node vocabularies deprecated in JSON-LD 1.1."
          end
          value
        when String, RDF::URI
          if RDF::URI(value.to_s).relative? && processingMode("json-ld-1.0")
            raise JsonLdError::InvalidVocabMapping, "@vocab must be an absolute IRI in 1.0 mode: #{value.inspect}"
          end

          expand_iri(value.to_s, vocab: true, documentRelative: true)
        when nil
          nil
        else
          raise JsonLdError::InvalidVocabMapping, "@vocab must be an IRI: #{value.inspect}"
        end
      end

      # Set propagation
      # @note: by the time this is called, the work has already been done.
      #
      # @param [Boolean] value
      def propagate=(value, **_options)
        if processingMode("json-ld-1.0")
          raise JsonLdError::InvalidContextEntry,
            "@propagate may only be set in 1.1 mode"
        end

        unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
          raise JsonLdError::InvalidPropagateValue,
            "@propagate must be boolean valued: #{value.inspect}"
        end

        value
      end

      ##
      # Generate @context
      #
      # If a context was supplied in global options, use that, otherwise, generate one
      # from this representation.
      #
      # @param [Array, Hash, Context, IO, StringIO] provided_context (nil)
      #   Original context to use, if available
      # @param  [Hash{Symbol => Object}] options ({})
      # @return [Hash]
      def serialize(provided_context: nil, **_options)
        # log_debug("serlialize: generate context")
        # log_debug("") {"=> context: #{inspect}"}
        use_context = case provided_context
        when String, RDF::URI
          # log_debug "serlialize: reuse context: #{provided_context.inspect}"
          provided_context.to_s
        when Hash
          # log_debug "serlialize: reuse context: #{provided_context.inspect}"
          # If it has an @context entry use it, otherwise it is assumed to be the body of a context
          provided_context.fetch('@context', provided_context)
        when Array
          # log_debug "serlialize: reuse context: #{provided_context.inspect}"
          provided_context
        when IO, StringIO
          load_context(provided_context, **@options).fetch('@context', {})
        else
          ctx = {}
          ctx['@version'] = 1.1 if @processingMode == 'json-ld-1.1'
          ctx['@base'] = base.to_s if base
          ctx['@direction'] = default_direction.to_s if default_direction
          ctx['@language'] = default_language.to_s if default_language
          ctx['@vocab'] = vocab.to_s if vocab

          # Term Definitions
          term_definitions.each do |term, defn|
            ctx[term] = defn.to_context_definition(self)
          end
          ctx
        end

        # Return hash with @context, or empty
        use_context.nil? || use_context.empty? ? {} : { '@context' => use_context }
      end

      ##
      # Build a context from an RDF::Vocabulary definition.
      #
      # @example building from an external vocabulary definition
      #
      #     g = RDF::Graph.load("http://schema.org/docs/schema_org_rdfa.html")
      #
      #     context = JSON::LD::Context.new.from_vocabulary(g,
      #           vocab: "http://schema.org/",
      #           prefixes: {schema: "http://schema.org/"},
      #           language: "en")
      #
      # @param [RDF::Queryable] graph
      #
      # @note requires rdf/vocab gem.
      #
      # @return [self]
      def from_vocabulary(graph)
        require 'rdf/vocab' unless RDF.const_defined?(:Vocab)
        statements = {}
        ranges = {}

        # Add term definitions for each class and property not in schema:, and
        # for those properties having an object range
        graph.each do |statement|
          next if statement.subject.node?

          (statements[statement.subject] ||= []) << statement

          # Keep track of predicate ranges
          if [RDF::RDFS.range, RDF::Vocab::SCHEMA.rangeIncludes].include?(statement.predicate)
            (ranges[statement.subject] ||= []) << statement.object
          end
        end

        # Add term definitions for each class and property not in vocab, and
        # for those properties having an object range
        statements.each do |subject, values|
          types = values.each_with_object([]) { |v, memo| memo << v.object if v.predicate == RDF.type }
          is_property = types.any? { |t| t.to_s.include?("Property") }

          term = subject.to_s.split(%r{[/\#]}).last

          if is_property
            prop_ranges = ranges.fetch(subject, [])
            # If any range is empty or member of range includes rdfs:Literal or schema:Text
            next if (vocab && prop_ranges.empty?) ||
                    prop_ranges.include?(RDF::Vocab::SCHEMA.Text) ||
                    prop_ranges.include?(RDF::RDFS.Literal)

            td = term_definitions[term] = TermDefinition.new(term, id: subject.to_s)

            # Set context typing based on first element in range
            case r = prop_ranges.first
            when RDF::XSD.string
              td.language_mapping = false if default_language
              # FIXME: text direction
            when RDF::XSD.boolean, RDF::Vocab::SCHEMA.Boolean, RDF::XSD.date, RDF::Vocab::SCHEMA.Date,
              RDF::XSD.dateTime, RDF::Vocab::SCHEMA.DateTime, RDF::XSD.time, RDF::Vocab::SCHEMA.Time,
              RDF::XSD.duration, RDF::Vocab::SCHEMA.Duration, RDF::XSD.decimal, RDF::Vocab::SCHEMA.Number,
              RDF::XSD.float, RDF::Vocab::SCHEMA.Float, RDF::XSD.integer, RDF::Vocab::SCHEMA.Integer
              td.type_mapping = r
              td.simple = false
            else
              # It's an object range (includes schema:URL)
              td.type_mapping = '@id'
            end
          else
            # Ignore if there's a default voabulary and this is not a property
            next if vocab && subject.to_s.start_with?(vocab)

            # otherwise, create a term definition
            td = term_definitions[term] = TermDefinition.new(term, id: subject.to_s)
          end
        end

        self
      end

      # Set term mapping
      #
      # @param [#to_s] term
      # @param [RDF::URI, String, nil] value
      #
      # @return [TermDefinition]
      def set_mapping(term, value)
        # log_debug("") {"map #{term.inspect} to #{value.inspect}"}
        term = term.to_s
        term_definitions[term] =
          TermDefinition.new(term, id: value, simple: true, prefix: value.to_s.end_with?(*PREFIX_URI_ENDINGS))
        term_definitions[term].simple = true

        term_sym = term.empty? ? "" : term.to_sym
        iri_to_term.delete(term_definitions[term].id.to_s) if term_definitions[term].id.is_a?(String)
        @options[:prefixes][term_sym] = value if @options.key?(:prefixes)
        iri_to_term[value.to_s] = term
        term_definitions[term]
      end

      ##
      # Find a term definition
      #
      # @param [Term, #to_s] term in unexpanded form
      # @return [Term]
      def find_definition(term)
        term.is_a?(TermDefinition) ? term : term_definitions[term.to_s]
      end

      ##
      # Retrieve container mapping, add it if `value` is provided
      #
      # @param [Term, #to_s] term in unexpanded form
      # @return [Array<'@index', '@language', '@index', '@set', '@type', '@id', '@graph'>]
      def container(term)
        return Set[term] if term == '@list'

        term = find_definition(term)
        term ? term.container_mapping : Set.new
      end

      ##
      # Retrieve term coercion
      #
      # @param [Term, #to_s] term in unexpanded form
      # @return [RDF::URI, '@id']
      def coerce(term)
        # Map property, if it's not an RDF::Value
        # @type is always is an IRI
        return '@id' if term == RDF.type || term == '@type'

        term = find_definition(term)
        term&.type_mapping
      end

      ##
      # Should values be represented using an array?
      #
      # @param [Term, #to_s] term in unexpanded form
      # @return [Boolean]
      def as_array?(term)
        return true if CONTEXT_CONTAINER_ARRAY_TERMS.include?(term)

        term = find_definition(term)
        term && (term.as_set? || term.container_mapping.include?('@list'))
      end

      ##
      # Retrieve content of a term
      #
      # @param [Term, #to_s] term in unexpanded form
      # @return [Hash]
      def content(term)
        term = find_definition(term)
        term&.content
      end

      ##
      # Retrieve nest of a term.
      # value of nest must be @nest or a term that resolves to @nest
      #
      # @param [Term, #to_s] term in unexpanded form
      # @return [String] Nesting term
      # @raise JsonLdError::InvalidNestValue if nesting term exists and is not a term resolving to `@nest` in the current context.
      def nest(term)
        term = find_definition(term)
        return unless term

        case term.nest
        when '@nest', nil
        else
          nest_term = find_definition(term.nest)
          unless nest_term && nest_term.id == '@nest'
            raise JsonLdError::InvalidNestValue,
              "nest must a term resolving to @nest, was #{nest_term.inspect}"
          end

        end
        term.nest
      end

      ##
      # Retrieve the language associated with a term, or the default language otherwise
      # @param [Term, #to_s] term in unexpanded form
      # @return [String]
      def language(term)
        term = find_definition(term)
        lang = term&.language_mapping
        if lang.nil?
          @default_language
        else
          (lang == false ? nil : lang)
        end
      end

      ##
      # Retrieve the text direction associated with a term, or the default direction otherwise
      # @param [Term, #to_s] term in unexpanded form
      # @return [String]
      def direction(term)
        term = find_definition(term)
        dir = term&.direction_mapping
        if dir.nil?
          @default_direction
        else
          (dir == false ? nil : dir)
        end
      end

      ##
      # Is this a reverse term
      # @param [Term, #to_s] term in unexpanded form
      # @return [Boolean]
      def reverse?(term)
        term = find_definition(term)
        term&.reverse_property
      end

      ##
      # Given a term or IRI, find a reverse term definition matching that term. If the term is already reversed, find a non-reversed version.
      #
      # @param [Term, #to_s] term
      # @return [Term] related term definition
      def reverse_term(term)
        # Direct lookup of term
        term = term_definitions[term.to_s] if term_definitions.key?(term.to_s) && !term.is_a?(TermDefinition)

        # Lookup term, assuming term is an IRI
        unless term.is_a?(TermDefinition)
          td = term_definitions.values.detect { |t| t.id == term.to_s }

          # Otherwise create a temporary term definition
          term = td || TermDefinition.new(term.to_s, id: expand_iri(term, vocab: true))
        end

        # Now, return a term, which reverses this term
        term_definitions.values.detect { |t| t.id == term.id && t.reverse_property != term.reverse_property }
      end

      ##
      # Expand an IRI. Relative IRIs are expanded against any document base.
      #
      # @param [String] value
      #   A keyword, term, prefix:suffix or possibly relative IRI
      # @param [Boolean] as_string (false) transform RDF::Resource values to string
      # @param [String, RDF::URI] base for resolving document-relative IRIs
      # @param [Hash] defined
      #   Used during Context Processing.
      # @param [Boolean] documentRelative (false)
      # @param [Hash] local_context
      #   Used during Context Processing.
      # @param [Boolean] vocab (false)
      # @param  [Hash{Symbol => Object}] options
      # @return [RDF::Resource, String]
      #   IRI or String, if it's a keyword
      # @raise [JSON::LD::JsonLdError::InvalidIRIMapping] if the value cannot be expanded
      # @see https://www.w3.org/TR/json-ld11-api/#iri-expansion
      def expand_iri(value,
                     as_string: false,
                     base: nil,
                     defined: nil,
                     documentRelative: false,
                     local_context: nil,
                     vocab: false,
                     **_options)
        return (value && as_string ? value.to_s : value) unless value.is_a?(String)

        return value if KEYWORDS.include?(value)
        return nil if value.match?(/^@[a-zA-Z]+$/)

        defined ||= {} # if we initialized in the keyword arg we would allocate {} at each invokation, even in the 2 (common) early returns above.

        # If local context is not null, it contains a key that equals value, and the value associated with the key that equals value in defined is not true, then invoke the Create Term Definition subalgorithm, passing active context, local context, value as term, and defined. This will ensure that a term definition is created for value in active context during Context Processing.
        create_term_definition(local_context, value, defined) if local_context&.key?(value) && !defined[value]

        if (v_td = term_definitions[value]) && KEYWORDS.include?(v_td.id)
          return (as_string ? v_td.id.to_s : v_td.id)
        end

        # If active context has a term definition for value, and the associated mapping is a keyword, return that keyword.
        # If vocab is true and the active context has a term definition for value, return the associated IRI mapping.
        if (v_td = term_definitions[value]) && (vocab || KEYWORDS.include?(v_td.id))
          iri = base && v_td.id ? base.join(v_td.id) : v_td.id # vocab might be doc relative
          return (as_string ? iri.to_s : iri)
        end

        # If value contains a colon (:), it is either an absolute IRI or a compact IRI:
        if value[1..].to_s.include?(':')
          prefix, suffix = value.split(':', 2)

          # If prefix is underscore (_) or suffix begins with double-forward-slash (//), return value as it is already an absolute IRI or a blank node identifier.
          if prefix == '_'
            v = RDF::Node.new(namer.get_sym(suffix))
            return (as_string ? v.to_s : v)
          end
          if suffix.start_with?('//')
            v = RDF::URI(value)
            return (as_string ? v.to_s : v)
          end

          # If local context is not null, it contains a key that equals prefix, and the value associated with the key that equals prefix in defined is not true, invoke the Create Term Definition algorithm, passing active context, local context, prefix as term, and defined. This will ensure that a term definition is created for prefix in active context during Context Processing.
          create_term_definition(local_context, prefix, defined) if local_context&.key?(prefix) && !defined[prefix]

          # If active context contains a term definition for prefix, return the result of concatenating the IRI mapping associated with prefix and suffix.
          if (td = term_definitions[prefix]) && !td.id.nil? && td.prefix?
            return (as_string ? td.id.to_s : td.id) + suffix
          elsif RDF::URI(value).absolute?
            # Otherwise, if the value has the form of an absolute IRI, return it
            return (as_string ? value.to_s : RDF::URI(value))
          end
        end

        iri = value.is_a?(RDF::URI) ? value : RDF::URI(value)
        result = if vocab && self.vocab
          # If vocab is true, and active context has a vocabulary mapping, return the result of concatenating the vocabulary mapping with value.
          # Note that @vocab could still be relative to a document base
          (base && self.vocab.is_a?(RDF::URI) && self.vocab.relative? ? base.join(self.vocab) : self.vocab) + value
        elsif documentRelative
          if iri.absolute?
            iri
          elsif self.base.is_a?(RDF::URI) && self.base.absolute?
            self.base.join(iri)
          elsif self.base == false
            # No resollution of `@base: null`
            iri
          elsif base && self.base
            base.join(self.base).join(iri)
          elsif base
            base.join(iri)
          else
            # Returns a relative IRI in an odd case.
            iri
          end
        elsif local_context && iri.relative?
          # If local context is not null and value is not an absolute IRI, an invalid IRI mapping error has been detected and processing is aborted.
          raise JSON::LD::JsonLdError::InvalidIRIMapping, "not an absolute IRI: #{value}"
        else
          iri
        end
        result && as_string ? result.to_s : result
      end

      # The following constants are used to reduce object allocations in #compact_iri below
      CONTAINERS_GRAPH = %w[@graph@id @graph@id@set].freeze
      CONTAINERS_GRAPH_INDEX = %w[@graph@index @graph@index@set].freeze
      CONTAINERS_GRAPH_INDEX_INDEX = %w[@graph@index @graph@index@set @index @index@set].freeze
      CONTAINERS_GRAPH_SET = %w[@graph @graph@set @set].freeze
      CONTAINERS_ID_TYPE = %w[@id @id@set @type @set@type].freeze
      CONTAINERS_ID_VOCAB = %w[@id @vocab @none].freeze
      CONTAINERS_INDEX_SET = %w[@index @index@set].freeze
      CONTAINERS_LANGUAGE = %w[@language @language@set].freeze
      CONTAINERS_VALUE = %w[@value].freeze
      CONTAINERS_VOCAB_ID = %w[@vocab @id @none].freeze

      ##
      # Compacts an absolute IRI to the shortest matching term or compact IRI
      #
      # @param [RDF::URI] iri
      # @param [String, RDF::URI] base for resolving document-relative IRIs
      # @param [Object] value
      #   Value, used to select among various maps for the same IRI
      # @param [Boolean] reverse
      #   specifies whether a reverse property is being compacted
      # @param [Boolean] vocab
      #   specifies whether the passed iri should be compacted using the active context's vocabulary mapping
      #
      # @return [String] compacted form of IRI
      # @see https://www.w3.org/TR/json-ld11-api/#iri-compaction
      def compact_iri(iri, base: nil, reverse: false, value: nil, vocab: nil)
        return if iri.nil?

        iri = iri.to_s

        if vocab && inverse_context.key?(iri)
          default_language = if default_direction
            "#{self.default_language}_#{default_direction}".downcase
          else
            (self.default_language || "@none").downcase
          end
          containers = []
          tl = "@language"
          tl_value = "@null"
          containers.concat(CONTAINERS_INDEX_SET) if index?(value) && !graph?(value)

          # If the value is a JSON Object with the key @preserve, use the value of @preserve.
          value = value['@preserve'].first if value.is_a?(Hash) && value.key?('@preserve')

          if reverse
            tl = "@type"
            tl_value = "@reverse"
            containers << '@set'
          elsif list?(value)
            # if value is a list object, then set type/language and type/language value to the most specific values that work for all items in the list as follows:
            containers << "@list" unless index?(value)
            list = value['@list']
            common_type = nil
            common_language = default_language if list.empty?
            list.each do |item|
              item_language = "@none"
              item_type = "@none"
              if value?(item)
                if item.key?('@direction')
                  item_language = "#{item['@language']}_#{item['@direction']}".downcase
                elsif item.key?('@language')
                  item_language = item['@language'].downcase
                elsif item.key?('@type')
                  item_type = item['@type']
                else
                  item_language = "@null"
                end
              else
                item_type = '@id'
              end
              common_language ||= item_language
              common_language = '@none' if item_language != common_language && value?(item)
              common_type ||= item_type
              common_type = '@none' if item_type != common_type
            end

            common_language ||= '@none'
            common_type ||= '@none'
            if common_type == '@none'
              tl_value = common_language
            else
              tl = '@type'
              tl_value = common_type
            end
          elsif graph?(value)
            # Prefer @index and @id containers, then @graph, then @index
            containers.concat(CONTAINERS_GRAPH_INDEX_INDEX) if index?(value)
            containers.concat(CONTAINERS_GRAPH) if value.key?('@id')

            # Prefer an @graph container next
            containers.concat(CONTAINERS_GRAPH_SET)

            # Lastly, in 1.1, any graph can be indexed on @index or @id, so add if we haven't already
            containers.concat(CONTAINERS_GRAPH_INDEX) unless index?(value)
            containers.concat(CONTAINERS_GRAPH) unless value.key?('@id')
            containers.concat(CONTAINERS_INDEX_SET) unless index?(value)
            containers << '@set'

            tl = '@type'
            tl_value = '@id'
          else
            if value?(value)
              # In 1.1, an language map can be used to index values using @none
              if value.key?('@language') && !index?(value)
                tl_value = value['@language'].downcase
                tl_value += "_#{value['@direction']}" if value['@direction']
                containers.concat(CONTAINERS_LANGUAGE)
              elsif value.key?('@direction') && !index?(value)
                tl_value = "_#{value['@direction']}"
              elsif value.key?('@type')
                tl_value = value['@type']
                tl = '@type'
              end
            else
              # In 1.1, an id or type map can be used to index values using @none
              containers.concat(CONTAINERS_ID_TYPE)
              tl = '@type'
              tl_value = '@id'
            end
            containers << '@set'
          end

          containers << '@none'

          # In 1.1, an index map can be used to index values using @none, so add as a low priority
          containers.concat(CONTAINERS_INDEX_SET) unless index?(value)
          # Values without type or language can use @language map
          containers.concat(CONTAINERS_LANGUAGE) if value?(value) && value.keys == CONTAINERS_VALUE

          tl_value ||= '@null'
          preferred_values = []
          preferred_values << '@reverse' if tl_value == '@reverse'
          if ['@id', '@reverse'].include?(tl_value) && value.is_a?(Hash) && value.key?('@id')
            t_iri = compact_iri(value['@id'], vocab: true, base: base)
            if (r_td = term_definitions[t_iri]) && r_td.id == value['@id']
              preferred_values.concat(CONTAINERS_VOCAB_ID)
            else
              preferred_values.concat(CONTAINERS_ID_VOCAB)
            end
          else
            tl = '@any' if list?(value) && value['@list'].empty?
            preferred_values.concat([tl_value, '@none'].compact)
          end
          preferred_values << '@any'

          # if containers included `@language` and preferred_values includes something of the form language-tag_direction, add just the _direction part, to select terms that have that direction.
          if (lang_dir = preferred_values.detect { |v| v.include?('_') })
            preferred_values << ('_' + lang_dir.split('_').last)
          end

          if (p_term = select_term(iri, containers, tl, preferred_values))
            return p_term
          end
        end

        # At this point, there is no simple term that iri can be compacted to. If vocab is true and active context has a vocabulary mapping:
        if vocab && self.vocab && iri.start_with?(self.vocab) && iri.length > self.vocab.length
          suffix = iri[self.vocab.length..]
          return suffix unless term_definitions.key?(suffix)
        end

        # The iri could not be compacted using the active context's vocabulary mapping. Try to create a compact IRI, starting by initializing compact IRI to null. This variable will be used to tore the created compact IRI, if any.
        candidates = []

        term_definitions.each do |term, td|
          # Skip term if `@prefix` is not true in term definition
          next unless td&.prefix?

          next if td&.id.nil? || td.id == iri || !td.match_iri?(iri)

          suffix = iri[td.id.length..]
          ciri = "#{term}:#{suffix}"
          candidates << ciri unless value && term_definitions.key?(ciri)
        end

        return candidates.min unless candidates.empty?

        # If we still don't have any terms and we're using standard_prefixes,
        # try those, and add to mapping
        if @options[:standard_prefixes]
          candidates = RDF::Vocabulary
            .select { |v| iri.start_with?(v.to_uri.to_s) && iri != v.to_uri.to_s }
            .map do |v|
              prefix = v.__name__.to_s.split('::').last.downcase
              set_mapping(prefix, v.to_uri.to_s)
              iri.sub(v.to_uri.to_s, "#{prefix}:").sub(/:$/, '')
            end

          return candidates.min unless candidates.empty?
        end

        # If iri could be confused with a compact IRI using a term in this context, signal an error
        term_definitions.each do |term, td|
          next unless td.prefix? && td.match_compact_iri?(iri)

          raise JSON::LD::JsonLdError::IRIConfusedWithPrefix, "Absolute IRI '#{iri}' confused with prefix '#{term}'"
        end

        return iri if vocab

        # transform iri to a relative IRI using the document's base IRI
        iri = remove_base(self.base || base, iri)
        # Make . relative if it has the form of a keyword.
        iri = "./#{iri}" if iri.match?(/^@[a-zA-Z]+$/)

        iri
      end

      ##
      # If active property has a type mapping in the active context set to @id or @vocab, a JSON object with a single member @id whose value is the result of using the IRI Expansion algorithm on value is returned.
      #
      # Otherwise, the result will be a JSON object containing an @value member whose value is the passed value. Additionally, an @type member will be included if there is a type mapping associated with the active property or an @language member if value is a string and there is language mapping associated with the active property.
      #
      # @param [String] property
      #   Associated property used to find coercion rules
      # @param [Hash, String] value
      #   Value (literal or IRI) to be expanded
      # @param [Boolean] useNativeTypes (false) use native representations
      # @param [Boolean] rdfDirection (nil) decode i18n datatype if i18n-datatype
      # @param [String, RDF::URI] base for resolving document-relative IRIs
      # @param  [Hash{Symbol => Object}] options
      #
      # @return [Hash] Object representation of value
      # @raise [RDF::ReaderError] if the iri cannot be expanded
      # @see https://www.w3.org/TR/json-ld11-api/#value-expansion
      def expand_value(property, value, useNativeTypes: false, rdfDirection: nil, base: nil, **_options)
        td = term_definitions.fetch(property, TermDefinition.new(property))

        # If the active property has a type mapping in active context that is @id, return a new JSON object containing a single key-value pair where the key is @id and the value is the result of using the IRI Expansion algorithm, passing active context, value, and true for document relative.
        if value.is_a?(String) && td.type_mapping == '@id'
          # log_debug("") {"as relative IRI: #{value.inspect}"}
          return { '@id' => expand_iri(value, documentRelative: true, base: base).to_s }
        end

        # If active property has a type mapping in active context that is @vocab, return a new JSON object containing a single key-value pair where the key is @id and the value is the result of using the IRI Expansion algorithm, passing active context, value, true for vocab, and true for document relative.
        if value.is_a?(String) && td.type_mapping == '@vocab'
          return { '@id' => expand_iri(value, vocab: true, documentRelative: true, base: base).to_s }
        end

        case value
        when RDF::URI, RDF::Node
          { '@id' => value.to_s }
        when Date, DateTime, Time
          lit = RDF::Literal.new(value)
          { '@value' => lit.to_s, '@type' => lit.datatype.to_s }
        else
          # Otherwise, initialize result to a JSON object with an @value member whose value is set to value.
          res = {}

          if td.type_mapping && !CONTAINERS_ID_VOCAB.include?(td.type_mapping.to_s)
            res['@type'] = td.type_mapping.to_s
          elsif value.is_a?(String)
            language = language(property)
            direction = direction(property)
            res['@language'] = language if language
            res['@direction'] = direction if direction
          end

          res.merge('@value' => value)
        end
      end

      ##
      # Compact a value
      #
      # @param [String] property
      #   Associated property used to find coercion rules
      # @param [Hash] value
      #   Value (literal or IRI), in full object representation, to be compacted
      # @param [String, RDF::URI] base for resolving document-relative IRIs
      #
      # @return [Hash] Object representation of value
      # @raise [JsonLdError] if the iri cannot be expanded
      # @see https://www.w3.org/TR/json-ld11-api/#value-compaction
      # FIXME: revisit the specification version of this.
      def compact_value(property, value, base: nil)
        # log_debug("compact_value") {"property: #{property.inspect}, value: #{value.inspect}"}

        indexing = index?(value) && container(property).include?('@index')
        language = language(property)
        direction = direction(property)

        result = if coerce(property) == '@id' && value.key?('@id') && (value.keys - %w[@id @index]).empty?
          # Compact an @id coercion
          # log_debug("") {" (@id & coerce)"}
          compact_iri(value['@id'], base: base)
        elsif coerce(property) == '@vocab' && value.key?('@id') && (value.keys - %w[@id @index]).empty?
          # Compact an @id coercion
          # log_debug("") {" (@id & coerce & vocab)"}
          compact_iri(value['@id'], vocab: true)
        elsif value.key?('@id')
          # log_debug("") {" (@id)"}
          # return value as is
          value
        elsif value['@type'] && value['@type'] == coerce(property)
          # Compact common datatype
          # log_debug("") {" (@type & coerce) == #{coerce(property)}"}
          value['@value']
        elsif coerce(property) == '@none' || value['@type']
          # use original expanded value
          value
        elsif !value['@value'].is_a?(String)
          # log_debug("") {" (native)"}
          indexing || !index?(value) ? value['@value'] : value
        elsif value['@language'].to_s.casecmp(language.to_s).zero? && value['@direction'] == direction
          # Compact language and direction
          indexing || !index?(value) ? value['@value'] : value
        else
          value
        end

        if result.is_a?(Hash) && result.key?('@type') && value['@type'] != '@json'
          # Compact values of @type
          c_type = if result['@type'].is_a?(Array)
            result['@type'].map { |t| compact_iri(t, vocab: true) }
          else
            compact_iri(result['@type'], vocab: true)
          end
          result = result.merge('@type' => c_type)
        end

        # If the result is an object, tranform keys using any term keyword aliases
        if result.is_a?(Hash) && result.keys.any? { |k| self.alias(k) != k }
          # log_debug("") {" (map to key aliases)"}
          new_element = {}
          result.each do |k, v|
            new_element[self.alias(k)] = v
          end
          result = new_element
        end

        # log_debug("") {"=> #{result.inspect}"}
        result
      end

      ##
      # Turn this into a source for a new instantiation
      # @param [Array<String>] aliases
      #   Other URLs to alias when preloading
      # @return [String]
      def to_rb(*aliases)
        canon_base = RDF::URI(context_base).canonicalize
        defn = []

        defn << "base: #{base.to_s.inspect}" if base
        defn << "language: #{default_language.inspect}" if default_language
        defn << "vocab: #{vocab.to_s.inspect}" if vocab
        defn << "processingMode: #{processingMode.inspect}" if processingMode
        term_defs = term_definitions.map do |term, td|
          "      " + term.inspect + " => " + td.to_rb
        end.sort
        defn << "term_definitions: {\n#{term_defs.join(",\n")}\n    }" unless term_defs.empty?
        %(# -*- encoding: utf-8 -*-
      # frozen_string_literal: true
      # This file generated automatically from #{context_base}
      require 'json/ld'
      class JSON::LD::Context
      ).gsub(/^      /, '') +
          %[  add_preloaded("#{canon_base}") do\n    new(] + defn.join(", ") + ")\n  end\n" +
          aliases.map { |a| %[  alias_preloaded("#{a}", "#{canon_base}")\n] }.join +
          "end\n"
      end

      def inspect
        v = %w([Context)
        v << "base=#{base}" if base
        v << "vocab=#{vocab}" if vocab
        v << "processingMode=#{processingMode}" if processingMode
        v << "default_language=#{default_language}" if default_language
        v << "default_direction=#{default_direction}" if default_direction
        v << "previous_context" if previous_context
        v << "term_definitions[#{term_definitions.length}]=#{term_definitions}"
        v.join(" ") + "]"
      end

      # Duplicate an active context, allowing it to be modified.
      def dup
        that = self
        ec = Context.new(unfrozen: true, **@options)
        ec.context_base = that.context_base
        ec.base = that.base unless that.base.nil?
        ec.default_direction = that.default_direction
        ec.default_language = that.default_language
        ec.previous_context = that.previous_context
        ec.processingMode = that.processingMode if that.instance_variable_get(:@processingMode)
        ec.vocab = that.vocab if that.vocab

        ec.instance_eval do
          @term_definitions = that.term_definitions.dup
          @iri_to_term = that.iri_to_term
        end
        ec
      end

      protected

      ##
      # Determine if `term` is a suitable term.
      # Term may be any valid JSON string.
      #
      # @param [String] term
      # @return [Boolean]
      def term_valid?(term)
        term.is_a?(String) && !term.empty?
      end

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

      private

      CONTEXT_CONTAINER_ARRAY_TERMS = Set.new(%w[@set @list @graph]).freeze
      CONTEXT_CONTAINER_ID_GRAPH = Set.new(%w[@id @graph]).freeze
      CONTEXT_CONTAINER_INDEX_GRAPH = Set.new(%w[@index @graph]).freeze
      CONTEXT_BASE_FRAG_OR_QUERY = %w[? #].freeze
      CONTEXT_TYPE_ID_VOCAB = %w[@id @vocab].freeze

      ##
      # Reads the `@context` from an IO
      def load_context(io, **options)
        io.rewind
        remote_doc = API.loadRemoteDocument(io, **options)
        if remote_doc.document.is_a?(String)
          MultiJson.load(remote_doc.document)
        else
          remote_doc.document
        end
      end

      def uri(value)
        case value.to_s
        when /^_:(.*)$/
          # Map BlankNodes if a namer is given
          # log_debug "uri(bnode)#{value}: #{$1}"
          bnode(namer.get_sym(::Regexp.last_match(1)))
        else
          RDF::URI(value)
          # value.validate! if options[:validate]

        end
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
      # Inverse Context creation
      #
      # When there is more than one term that could be chosen to compact an IRI, it has to be ensured that the term selection is both deterministic and represents the most context-appropriate choice whilst taking into consideration algorithmic complexity.
      #
      # In order to make term selections, the concept of an inverse context is introduced. An inverse context is essentially a reverse lookup table that maps container mappings, type mappings, and language mappings to a simple term for a given active context. A inverse context only needs to be generated for an active context if it is being used for compaction.
      #
      # To make use of an inverse context, a list of preferred container mappings and the type mapping or language mapping are gathered for a particular value associated with an IRI. These parameters are then fed to the Term Selection algorithm, which will find the term that most appropriately matches the value's mappings.
      #
      # @example Basic structure of resulting inverse context
      #     {
      #       "http://example.com/term": {
      #         "@language": {
      #           "@null": "term",
      #           "@none": "term",
      #           "en": "term",
      #           "ar_rtl": "term"
      #         },
      #         "@type": {
      #           "@reverse": "term",
      #           "@none": "term",
      #           "http://datatype": "term"
      #         },
      #         "@any": {
      #           "@none": "term",
      #         }
      #       }
      #     }
      # @return [Hash{String => Hash{String => String}}]
      # @todo May want to include @set along with container to allow selecting terms using @set over those without @set. May require adding some notion of value cardinality to compact_iri
      def inverse_context
        Context.inverse_cache[hash] ||= begin
          result = {}
          default_language = (self.default_language || '@none').downcase
          term_definitions.keys.sort do |a, b|
            a.length == b.length ? (a <=> b) : (a.length <=> b.length)
          end.each do |term|
            next unless (td = term_definitions[term])

            container = td.container_mapping.to_a.join
            if container.empty?
              container = td.as_set? ? %(@set) : %(@none)
            end

            container_map = result[td.id.to_s] ||= {}
            tl_map = container_map[container] ||= { '@language' => {}, '@type' => {}, '@any' => {} }
            type_map = tl_map['@type']
            language_map = tl_map['@language']
            any_map = tl_map['@any']
            any_map['@none'] ||= term
            if td.reverse_property
              type_map['@reverse'] ||= term
            elsif td.type_mapping == '@none'
              type_map['@any'] ||= term
              language_map['@any'] ||= term
              any_map['@any'] ||= term
            elsif td.type_mapping
              type_map[td.type_mapping.to_s] ||= term
            elsif !td.language_mapping.nil? && !td.direction_mapping.nil?
              lang_dir = if td.language_mapping && td.direction_mapping
                "#{td.language_mapping}_#{td.direction_mapping}".downcase
              elsif td.language_mapping
                td.language_mapping.downcase
              elsif td.direction_mapping
                "_#{td.direction_mapping}"
              else
                "@null"
              end
              language_map[lang_dir] ||= term
            elsif !td.language_mapping.nil?
              lang_dir = (td.language_mapping || '@null').downcase
              language_map[lang_dir] ||= term
            elsif !td.direction_mapping.nil?
              lang_dir = td.direction_mapping ? "_#{td.direction_mapping}" : '@none'
              language_map[lang_dir] ||= term
            elsif default_direction
              language_map["_#{default_direction}"] ||= term
              language_map['@none'] ||= term
              type_map['@none'] ||= term
            else
              language_map[default_language] ||= term
              language_map['@none'] ||= term
              type_map['@none'] ||= term
            end
          end
          result
        end
      end

      ##
      # This algorithm, invoked via the IRI Compaction algorithm, makes use of an active context's inverse context to find the term that is best used to compact an IRI. Other information about a value associated with the IRI is given, including which container mappings and which type mapping or language mapping would be best used to express the value.
      #
      # @param [String] iri
      # @param [Array<String>] containers
      #   represents an ordered list of preferred container mappings
      # @param [String] type_language
      #   indicates whether to look for a term with a matching type mapping or language mapping
      # @param [Array<String>] preferred_values
      #   for the type mapping or language mapping
      # @return [String]
      def select_term(iri, containers, type_language, preferred_values)
        # log_debug("select_term") {
        #  "iri: #{iri.inspect}, " +
        #  "containers: #{containers.inspect}, " +
        #  "type_language: #{type_language.inspect}, " +
        #  "preferred_values: #{preferred_values.inspect}"
        # }
        container_map = inverse_context[iri]
        # log_debug("  ") {"container_map: #{container_map.inspect}"}
        containers.each do |container|
          next unless container_map.key?(container)

          tl_map = container_map[container]
          value_map = tl_map[type_language]
          preferred_values.each do |item|
            next unless value_map.key?(item)

            # log_debug("=>") {value_map[item].inspect}
            return value_map[item]
          end
        end
        # log_debug("=>") {"nil"}
        nil
      end

      ##
      # Removes a base IRI from the given absolute IRI.
      #
      # @param [String] base the base used for making `iri` relative
      # @param [String] iri the absolute IRI
      # @return [String]
      #   the relative IRI if relative to base, otherwise the absolute IRI.
      def remove_base(base, iri)
        return iri unless base

        @base_and_parents ||= begin
          u = base
          iri_set = u.to_s.end_with?('/') ? [u.to_s] : []
          iri_set << u.to_s while u != './' && (u = u.parent)
          iri_set
        end
        b = base.to_s
        return iri[b.length..] if iri.start_with?(b) && CONTEXT_BASE_FRAG_OR_QUERY.include?(iri[b.length, 1])

        @base_and_parents.each_with_index do |bb, index|
          next unless iri.start_with?(bb)

          rel = ("../" * index) + iri[bb.length..]
          return rel.empty? ? "./" : rel
        end
        iri
      end

      ## Used for testing
      # Retrieve term mappings
      #
      # @return [Array<RDF::URI>]
      def mappings
        {}.tap do |memo|
          term_definitions.each_pair do |t, td|
            memo[t] = td ? td.id : nil
          end
        end
      end

      ## Used for testing
      # Retrieve term mapping
      #
      # @param [String, #to_s] term
      #
      # @return [RDF::URI, String]
      def mapping(term)
        term_definitions[term]&.id
      end

      ## Used for testing
      # Retrieve language mappings
      #
      # @return [Array<String>]
      # @deprecated
      def languages
        {}.tap do |memo|
          term_definitions.each_pair do |t, td|
            memo[t] = td.language_mapping
          end
        end
      end

      # Ensure @container mapping is appropriate
      # The result is the original container definition. For IRI containers, this is necessary to be able to determine the @type mapping for string values
      def check_container(container, _local_context, _defined, term)
        if container.is_a?(Array) && processingMode('json-ld-1.0')
          raise JsonLdError::InvalidContainerMapping,
            "'@container' on term #{term.inspect} must be a string: #{container.inspect}"
        end

        val = Set.new(Array(container))
        val.delete('@set') if (has_set = val.include?('@set'))

        if val.include?('@list')
          unless !has_set && val.length == 1
            raise JsonLdError::InvalidContainerMapping,
              "'@container' on term #{term.inspect} using @list cannot have any other values"
          end
          # Okay
        elsif val.include?('@language')
          if has_set && processingMode('json-ld-1.0')
            raise JsonLdError::InvalidContainerMapping,
              "unknown mapping for '@container' to #{container.inspect} on term #{term.inspect}"
          end
          unless val.length == 1
            raise JsonLdError::InvalidContainerMapping,
              "'@container' on term #{term.inspect} using @language cannot have any values other than @set, found  #{container.inspect}"
          end
          # Okay
        elsif val.include?('@index')
          if has_set && processingMode('json-ld-1.0')
            raise JsonLdError::InvalidContainerMapping,
              "unknown mapping for '@container' to #{container.inspect} on term #{term.inspect}"
          end
          unless (val - CONTEXT_CONTAINER_INDEX_GRAPH).empty?
            raise JsonLdError::InvalidContainerMapping,
              "'@container' on term #{term.inspect} using @index cannot have any values other than @set and/or @graph, found  #{container.inspect}"
          end
          # Okay
        elsif val.include?('@id')
          if processingMode('json-ld-1.0')
            raise JsonLdError::InvalidContainerMapping,
              "unknown mapping for '@container' to #{container.inspect} on term #{term.inspect}"
          end
          unless val.subset?(CONTEXT_CONTAINER_ID_GRAPH)
            raise JsonLdError::InvalidContainerMapping,
              "'@container' on term #{term.inspect} using @id cannot have any values other than @set and/or @graph, found  #{container.inspect}"
          end
          # Okay
        elsif val.include?('@type') || val.include?('@graph')
          if processingMode('json-ld-1.0')
            raise JsonLdError::InvalidContainerMapping,
              "unknown mapping for '@container' to #{container.inspect} on term #{term.inspect}"
          end
          unless val.length == 1
            raise JsonLdError::InvalidContainerMapping,
              "'@container' on term #{term.inspect} using @language cannot have any values other than @set, found  #{container.inspect}"
          end
          # Okay
        elsif val.empty?
          # Okay
        else
          raise JsonLdError::InvalidContainerMapping,
            "unknown mapping for '@container' to #{container.inspect} on term #{term.inspect}"
        end
        Array(container)
      end

      # Term Definitions specify how properties and values have to be interpreted as well as the current vocabulary mapping and the default language
      class TermDefinition
        # @return [RDF::URI] IRI map
        attr_accessor :id

        # @return [String] term name
        attr_accessor :term

        # @return [String] Type mapping
        attr_accessor :type_mapping

        # Base container mapping, without @set
        # @return [Array<'@index', '@language', '@index', '@set', '@type', '@id', '@graph'>] Container mapping
        attr_reader :container_mapping

        # @return [String] Term used for nest properties
        attr_accessor :nest

        # Language mapping of term, `false` is used if there is an explicit language mapping for this term.
        # @return [String] Language mapping
        attr_accessor :language_mapping

        # Direction of term, `false` is used if there is explicit direction mapping mapping for this term.
        # @return ["ltr", "rtl"] direction_mapping
        attr_accessor :direction_mapping

        # @return [Boolean] Reverse Property
        attr_accessor :reverse_property

        # This is a simple term definition, not an expanded term definition
        # @return [Boolean]
        attr_accessor :simple

        # Property used for data indexing; defaults to @index
        # @return [Boolean]
        attr_accessor :index

        # Indicate that term may be used as a prefix
        attr_writer :prefix

        # Term-specific context
        # @return [Hash{String => Object}]
        attr_accessor :context

        # Term is protected.
        # @return [Boolean]
        attr_writer :protected

        # This is a simple term definition, not an expanded term definition
        # @return [Boolean] simple
        def simple?
          simple
        end

        # This is an appropriate term to use as the prefix of a compact IRI
        # @return [Boolean] simple
        def prefix?
          @prefix
        end

        # Create a new Term Mapping with an ID
        # @param [String] term
        # @param [String] id
        # @param [String] type_mapping Type mapping
        # @param [Set<'@index', '@language', '@index', '@set', '@type', '@id', '@graph'>] container_mapping
        # @param [String] language_mapping
        #   Language mapping of term, `false` is used if there is an explicit language mapping for this term
        # @param ["ltr", "rtl"] direction_mapping
        #   Direction mapping of term, `false` is used if there is an explicit direction mapping for this term
        # @param [Boolean] reverse_property
        # @param [Boolean] protected mark resulting context as protected
        # @param [String] nest term used for nest properties
        # @param [Boolean] simple
        #   This is a simple term definition, not an expanded term definition
        # @param [Boolean] prefix
        #   Term may be used as a prefix
        def initialize(term,
                       id: nil,
                       index: nil,
                       type_mapping: nil,
                       container_mapping: nil,
                       language_mapping: nil,
                       direction_mapping: nil,
                       reverse_property: false,
                       nest: nil,
                       protected: nil,
                       simple: false,
                       prefix: nil,
                       context: nil)
          @term                   = term
          @id                     = id.to_s           unless id.nil?
          @index                  = index.to_s        unless index.nil?
          @type_mapping           = type_mapping.to_s unless type_mapping.nil?
          self.container_mapping  = container_mapping
          @language_mapping       = language_mapping  unless language_mapping.nil?
          @direction_mapping      = direction_mapping unless direction_mapping.nil?
          @reverse_property       = reverse_property
          @protected              = protected
          @nest                   = nest unless nest.nil?
          @simple                 = simple
          @prefix                 = prefix            unless prefix.nil?
          @context                = context           unless context.nil?
        end

        # Term is protected.
        # @return [Boolean]
        def protected?
          !!@protected
        end

        # Returns true if the term matches a IRI
        #
        # @param iri [String] the IRI
        # @return [Boolean]
        def match_iri?(iri)
          iri.start_with?(id)
        end

        # Returns true if the term matches a compact IRI
        #
        # @param iri [String] the compact IRI
        # @return [Boolean]
        def match_compact_iri?(iri)
          iri.start_with?(prefix_colon)
        end

        # Set container mapping, from an array which may include @set
        def container_mapping=(mapping)
          mapping = case mapping
          when Set then mapping
          when Array then Set.new(mapping)
          when String then Set[mapping]
          when nil then Set.new
          else
            raise "Shouldn't happen with #{mapping.inspect}"
          end
          if (@as_set = mapping.include?('@set'))
            mapping = mapping.dup
            mapping.delete('@set')
          end
          @container_mapping = mapping
          @index ||= '@index' if mapping.include?('@index')
        end

        ##
        # Output Hash or String definition for this definition considering @language and @vocab
        #
        # @param [Context] context
        # @return [String, Hash{String => Array[String], String}]
        def to_context_definition(context)
          cid = if context.vocab && id.start_with?(context.vocab)
            # Nothing to return unless it's the same as the vocab
            id == context.vocab ? context.vocab : id.to_s[context.vocab.length..]
          else
            # Find a term to act as a prefix
            iri, prefix = context.iri_to_term.detect { |i, _p| id.to_s.start_with?(i.to_s) }
            iri && iri != id ? "#{prefix}:#{id.to_s[iri.length..]}" : id
          end

          if simple?
            cid.to_s unless cid == term && context.vocab
          else
            defn = {}
            defn[reverse_property ? '@reverse' : '@id'] = cid.to_s unless cid == term && !reverse_property
            if type_mapping
              defn['@type'] = if KEYWORDS.include?(type_mapping)
                type_mapping
              else
                context.compact_iri(type_mapping, vocab: true)
              end
            end

            cm = Array(container_mapping)
            cm << "@set" if as_set? && !cm.include?("@set")
            cm = cm.first if cm.length == 1
            defn['@container'] = cm unless cm.empty?
            # Language set as false to be output as null
            defn['@language'] = (@language_mapping || nil) unless @language_mapping.nil?
            defn['@direction'] = (@direction_mapping || nil) unless @direction_mapping.nil?
            defn['@context'] = @context if @context
            defn['@nest'] = @nest if @nest
            defn['@index'] = @index if @index
            defn['@prefix'] = @prefix unless @prefix.nil?
            defn
          end
        end

        ##
        # Turn this into a source for a new instantiation
        # FIXME: context serialization
        # @return [String]
        def to_rb
          defn = [%(TermDefinition.new\(#{term.inspect})]
          %w[id index type_mapping container_mapping language_mapping direction_mapping reverse_property nest simple
             prefix context protected].each do |acc|
            v = instance_variable_get("@#{acc}".to_sym)
            v = v.to_s if v.is_a?(RDF::Term)
            if acc == 'container_mapping'
              v = v.to_a
              v << '@set' if as_set?
              v = v.first if v.length <= 1
            end
            defn << "#{acc}: #{v.inspect}" if v
          end
          defn.join(', ') + ")"
        end

        # If container mapping was defined along with @set
        # @return [Boolean]
        def as_set?
          @as_set || false
        end

        # Check if term definitions are identical, modulo @protected
        # @return [Boolean]
        def ==(other)
          other.is_a?(TermDefinition) &&
            id == other.id &&
            term == other.term &&
            type_mapping == other.type_mapping &&
            container_mapping == other.container_mapping &&
            nest == other.nest &&
            language_mapping == other.language_mapping &&
            direction_mapping == other.direction_mapping &&
            reverse_property == other.reverse_property &&
            index == other.index &&
            context == other.context &&
            prefix? == other.prefix? &&
            as_set? == other.as_set?
        end

        def inspect
          v = %w([TD)
          v << "id=#{@id}"
          v << "index=#{index.inspect}" unless index.nil?
          v << "term=#{@term}"
          v << "rev" if reverse_property
          v << "container=#{container_mapping}" if container_mapping
          v << "as_set=#{as_set?.inspect}"
          v << "lang=#{language_mapping.inspect}" unless language_mapping.nil?
          v << "dir=#{direction_mapping.inspect}" unless direction_mapping.nil?
          v << "type=#{type_mapping}" unless type_mapping.nil?
          v << "nest=#{nest.inspect}" unless nest.nil?
          v << "simple=true" if @simple
          v << "protected=true" if @protected
          v << "prefix=#{@prefix.inspect}" unless @prefix.nil?
          v << "has-context" unless context.nil?
          v.join(" ") + "]"
        end

        private

        def prefix_colon
          @prefix_colon ||= "#{term}:".freeze
        end
      end
    end
  end
end
