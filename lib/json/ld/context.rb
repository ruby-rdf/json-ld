require 'open-uri'
require 'json'
require 'bigdecimal'

module JSON::LD
  class Context
    include Utils

    # Term Definitions specify how properties and values have to be interpreted as well as the current vocabulary mapping and the default language
    class TermDefinition
      # @return [String, Array[String]] IRI mapping
      attr_accessor :id

      # @return [String] Type mapping
      attr_accessor :type_mapping

      # @return [String] Container mapping
      attr_accessor :container_mapping

      # Language mapping of term, `false` is used if there is explicitly no language mapping for this term.
      # @return [String] Language mapping
      attr_accessor :language_mapping

      # @return [Boolean] Reverse Property
      attr_accessor :reverse_property

      # Create a new Term Mapping with an ID
      # @param [String, Array[String]] id
      def initialize(id = nil)
        @id = id
      end

      # Output Hash or String definition for this definition
      # @return [String, Hash{String => Array[String], String}]
      def to_context_definition
        if language_mapping.nil? &&
           container_mapping.nil? &&
           type_mapping.nil? &&
           reverse_property.nil?
          id
        else
          defn = Hash.ordered
          defn[reverse_property ? '@reverse' : '@id'] = id
          defn['@type'] = type_mapping if type_mapping
          defn['@container'] = container_mapping if container_mapping
          # Language set as false to be output as null
          defn['@language'] = (language_mapping ? language_mapping : nil) unless language_mapping.nil?
          defn
        end
      end

      def inspect
        v = %w([TD)
        v << "id=#{@id}"
        v << "rev" if reverse_property
        v << "container=#{container_mapping}" if container_mapping
        v << "lang=#{language_mapping.inspect}" unless language_mapping.nil?
        v << "type=#{type_mapping}" unless type_mapping.nil?
        v.join(" ") + "]"
      end
    end

    # The base.
    #
    # @return [RDF::URI] Document base IRI, used for expanding relative IRIs.
    attr_reader :base

    # @return [RDF::URI] base IRI of the context, if loaded remotely. XXX
    attr_accessor :context_base

    # Term definitions
    # @!attribute [r] term_definitions
    # @return [Hash{String => TermDefinition}]
    attr_reader :term_definitions

    # @return [Hash{RDF::URI => String}] Reverse mappings from IRI to term only for terms, not CURIEs XXX
    attr_accessor :iri_to_term

    # Default language
    #
    #
    # This adds a language to plain strings that aren't otherwise coerced
    # @!attribute [rw] default_language
    # @return [String]
    attr_reader :default_language
    
    # Default vocabulary
    #
    # Sets the default vocabulary used for expanding terms which
    # aren't otherwise absolute IRIs
    # @return [String]
    attr_reader :vocab

    # @return [Hash{Symbol => Object}] Global options used in generating IRIs
    attr_accessor :options

    # @return [Context] A context provided to us that we can use without re-serializing XXX
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
      @orig_base = @base = RDF::URI(options[:base]) if options[:base]
      @term_definitions = {}
      @iri_to_term = {
        RDF.to_uri.to_s => "rdf",
        RDF::XSD.to_uri.to_s => "xsd"
      }
      @remote_contexts = []
      @namer = BlankNodeMapper.new("t")

      @options = options

      # Load any defined prefixes
      (options[:prefixes] || {}).each_pair do |k, v|
        @iri_to_term[v.to_s] = k unless k.nil?
      end

      debug("init") {"iri_to_term: #{iri_to_term.inspect}"}
      
      yield(self) if block_given?
    end

    # @param [String] value must be an absolute IRI
    def base=(value)
      if value
        raise InvalidContext::InvalidBaseIRI, "@base must be a string: #{value.inspect}" unless value.is_a?(String)
        @base = RDF::URI(value)
        raise InvalidContext::InvalidBaseIRI, "@base must be an absolute IRI: #{value.inspect}" unless @base.absolute?
        @base
      else
        @base = @orig_base
      end

    end

    # @param [String] value
    def default_language=(value)
      @default_language = if value
        raise InvalidContext::InvalidDefaultLanguage, "@language must be a string: #{value.inspect}" unless value.is_a?(String)
        value.downcase
      else
        nil
      end
    end

    # @param [String] value must be an absolute IRI
    def vocab=(value)
      if value
        raise InvalidContext::InvalidVocabMapping, "@value must be a string: #{value.inspect}" unless value.is_a?(String)
        @vocab = RDF::URI(value)
        raise InvalidContext::InvalidVocabMapping, "@value must be an absolute IRI: #{value.inspect}" unless @vocab.absolute?
        @vocab
      else
        @vocab = nil
      end
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
    # @raise [InvalidContext]
    #   on a remote context load error, syntax error, or a reference to a term which is not defined.
    # @see http://json-ld.org/spec/latest/json-ld-api/index.html#context-processing-algorithm
    def parse(local_context, remote_contexts = [])
      result = self.dup
      local_context = [local_context] unless local_context.is_a?(Array)

      local_context.each do |context|
        depth do
          case context
          when nil
            # 3.1 If niil, set to a new empty context
            result = Context.new(options)
          when IO, StringIO
            debug("parse") {"io: #{context}"}
            # Load context document, if it is a string
            begin
              ctx = JSON.load(context)
              raise JSON::LD::InvalidContext::InvalidRemoteContext, "Context missing @context key" if @options[:validate] && ctx['@context'].nil?
              parse(ctx["@context"] || {})
            rescue JSON::ParserError => e
              debug("parse") {"Failed to parse @context from remote document at #{context}: #{e.message}"}
              raise JSON::LD::InvalidContext::InvalidRemoteContext, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
              self.dup
            end
          when String
            debug("parse") {"remote: #{context}, base: #{result.context_base || result.base}"}
            # Load context document, if it is a string
            begin
              # 3.2.1) Set context to the result of resolving value against the base IRI which is established as specified in section 5.1 Establishing a Base URI of [RFC3986]. Only the basic algorithm in section 5.2 of [RFC3986] is used; neither Syntax-Based Normalization nor Scheme-Based Normalization are performed. Characters additionally allowed in IRI references are treated in the same way that unreserved characters are treated in URI references, per section 6.5 of [RFC3987].
              context = RDF::URI(result.context_base || result.base).join(context)

              raise InvalidContext::RecursiveContextInclusion, "#{context}" if remote_contexts.include?(context)
              @remote_contexts = @remote_contexts + [context]

              context_no_base = self.dup
              context_no_base.base = nil
              context_no_base.provided_context = context
              context_no_base.context_base = context

              RDF::Util::File.open_file(context) do |f|
                # 3.2.5) Dereference context. If the dereferenced document has no top-level JSON object with an @context member, an invalid remote context has been detected and processing is aborted; otherwise, set context to the value of that member.
                jo = JSON.load(f)
                raise InvalidContext::InvalidRemoteContext, "#{context}" unless jo.is_a?(Hash) && jo.has_key?('@context')
                context = jo['@context']
              end

              # 3.2.6) Set context to the result of recursively calling this algorithm, passing context no base for active context, context for local context, and remote contexts.
              context = context_no_base.parse(context, remote_contexts.dup)
              context.base = result.base unless result.base.nil?
              result = context
              debug("parse") {"=> provided_context: #{context.inspect}"}
            rescue Exception => e
              debug("parse") {"Failed to retrieve @context from remote document at #{context.inspect}: #{e.message}"}
              raise InvalidContext::InvalidRemoteContext, "#{context}", e.backtrace if @options[:validate]
            end
          when Hash
            # If context has a @vocab member: if its value is not a valid absolute IRI or null trigger an INVALID_VOCAB_MAPPING error; otherwise set the active context's vocabulary mapping to its value and remove the @vocab member from context.
            {
              '@base' => :base=,
              '@language' => :default_language=,
              '@vocab'    => :vocab=
            }.each do |key, setter|
              v = context.fetch(key, false)
              unless v == false
                context.delete(key)
                debug("parse") {"Set #{key} to #{v.inspect}"}
                result.send(setter, v)
              end
            end

            defined = {}
          # For each key-value pair in context invoke the Create Term Definition subalgorithm, passing result for active context, context for local context, key, and defined
            depth do
              context.keys.each do |key|
                result.create_term_definition(context, key, defined)
              end
            end
          else
            # 3.3) If context is not a JSON object, an invalid local context error has been detected and processing is aborted.
            raise InvalidContext::InvalidLocalContext
          end
        end
      end
      result
    end


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
    # @raise [InvalidContext]
    #   Represents a cyclical term dependency
    # @see http://json-ld.org/spec/latest/json-ld-api/index.html#create-term-definition
    def create_term_definition(local_context, term, defined)
      # Expand a string value, unless it matches a keyword
      debug("create_term_definition") {"term = #{term.inspect}"}

      # If defined contains the key term, then the associated value must be true, indicating that the term definition has already been created, so return. Otherwise, a cyclical term definition has been detected, which is an error.
      case defined[term]
      when TrueClass then return
      when nil
        defined[term] = false
      else
        raise InvalidContext::CyclicIRIMapping, "Cyclical term dependency found for #{term.inspect}"
      end

      # Since keywords cannot be overridden, term must not be a keyword. Otherwise, an invalid value has been detected, which is an error.
      if KEYWORDS.include?(term) && !%w(@vocab @language).include?(term)
        raise InvalidContext::KeywordRedefinition, "term #{term.inspect} must not be a keyword" if
          @options[:validate]
      elsif !term_valid?(term) && @options[:validate]
        raise InvalidContext::InvalidTermDefinition, "term #{term.inspect} is invalid"
      end

      # Remove any existing term definition for term in active context.
      term_definitions.delete(term)

      # Initialize value to a the value associated with the key term in local context.
      value = local_context.fetch(term, false)
      value = {'@id' => value} if value.is_a?(String)

      case value
      when nil, {'@id' => nil}
        # If value equals null or value is a JSON object containing the key-value pair (@id-null), then set the term definition in active context to null, set the value associated with defined's key term to true, and return.
        debug(" =>") {"nil"}
        term_definitions[term] = TermDefinition.new
        defined[term] = true
        return
      when Hash
        debug("create_term_definition") {"Hash[#{term.inspect}] = #{value.inspect}"}
        definition = TermDefinition.new

        if value.has_key?('@reverse')
          raise InvalidContext::InvalidReverseProperty, "unexpected key in #{value.inspect}" if
            value.keys.any? {|k| ['@id', '@type', '@language'].include?(k)}
          raise InvalidContext::InvalidIRIMapping, "expected value of @reverse to be a string" unless
            value['@reverse'].is_a?(String)

          # Otherwise, set the IRI mapping of definition to the result of using the IRI Expansion algorithm, passing active context, the value associated with the @reverse key for value, true for vocab, true for document relative, local context, and defined. If the result is not an absolute IRI, i.e., it contains no colon (:), an invalid IRI mapping error has been detected and processing is aborted.
          definition.id =  expand_iri(value['@reverse'],
                                      :vocab => true,
                                      :documentRelative => true,
                                      :local_context => local_context,
                                      :defined => defined)
          raise InvalidContext::InvalidIRImapping, "non-absolute @reverse IRI: #{definition.id}" unless
            definition.id.absolute?
          definition.type_mapping = '@id'

          # If value contains an @container member, set the container mapping of definition to @index if that is the value of the @container member; otherwise an invalid reverse property error has been detected (reverse properties only support index-containers) and processing is aborted.
          if (container = value['@container']) && container != '@index'
            raise InvalidContext::InvalidReverseProperty, "unknown mapping for '@container' to #{container.inspect}"
          end
          definition.reverse_property = true
        elsif value.has_key?('@id') && value['@id'] != term
          raise InvalidContext::InvalidIRIMapping, "expected value of @reverse to be a string" unless
            value['@id'].is_a?(String)
          definition.id = expand_iri(value['@id'],
            :vocab => true,
            :documentRelative => true,
            :local_context => local_context,
            :defined => defined)
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
          raise InvalidContext::InvalidIRIMapping, "relative term definition without vocab" unless vocab
          definition.id = vocab + term
          debug(" =>") {definition.id}
        end

        if value.has_key?('@type')
          type = value['@type']
          # SPEC FIXME: @type may be nil
          raise InvalidContext::InvalidTypeMapping, "unknown mapping for '@type' to #{type.inspect}" unless type.is_a?(String) || type.nil?
          type = expand_iri(type, :vocab => true, :documentRelative => true, :local_context => local_context, :defined => defined) if type.is_a?(String)
          debug("create_term_definition") {"type_mapping: #{type.inspect}"}
          definition.type_mapping = type
        end

        if value.has_key?('@container')
          container = value['@container']
          raise InvalidContext::InvalidContainerMapping, "unknown mapping for '@container' to #{container.inspect}" unless %w(@list @set @language @index).include?(container)
          debug("create_term_definition") {"container_mapping: #{container.inspect}"}
          definition.container_mapping = container
        end

        if value.has_key?('@language')
          language = value['@language']
          raise InvalidContext::InvalidLanguageMapping, "language must be null or a string, was #{language.inspect}}" unless language.nil? || (language || "").is_a?(String)
          language = language.downcase if language.is_a?(String)
          debug("create_term_definition") {"language_mapping: #{language.inspect}"}
          definition.language_mapping = language || false
        end

        term_definitions[term] = definition
        defined[term] = true
      else
        raise InvalidContext::InvalidTermDefinition, "Term definition for #{term.inspect} is an #{value.class}"
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
        # FIXME: not setting provided_context now
        use_context = if provided_context
          debug "serlialize: reuse context: #{provided_context.inspect}"
          provided_context.to_s
        else
          debug("serlialize: generate context")
          debug {"=> context: #{inspect}"}
          ctx = Hash.ordered
          ctx['@base'] = base.to_s if base
          ctx['@language'] = default_language.to_s if default_language
          ctx['@vocab'] = vocab.to_s if vocab

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
      term_definitions[property] && term_definitions[property].type_mapping
    end
    protected :coerce

    ##
    # Retrieve container mapping, add it if `value` is provided
    #
    # @param [String] property in unexpanded form
    # @return [String]
    def container(property)
      return '@set' if property == '@graph'
      return property if KEYWORDS.include?(property)
      term_definitions[property] && term_definitions[property].container_mapping
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
    def language(property)
      lang = term_definitions[property] && term_definitions[property].language_mapping
      lang || @default_language
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
    protected :term_valid?

    ##
    # Expand an IRI. Relative IRIs are expanded against any document base.
    #
    # @param [String] value
    #   A keyword, term, prefix:suffix or possibly relative IRI
    # @param  [Hash{Symbol => Object}] options
    # @option options [Boolean] documentRelative (false)
    # @option options [Boolean] vocab (false)
    # @option options [Hash] local_context
    #   Used during Context Processing.
    # @option options [Hash] defined
    #   Used during Context Processing.
    # @return [RDF::URI, String]
    #   IRI or String, if it's a keyword
    # @raise [JSON::LD::InvalidContext::InvalidIRIMapping] if the value cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-expansion
    def expand_iri(value, options = {})
      return value unless value.is_a?(String)

      return value if KEYWORDS.include?(value)
      depth(options) do
        local_context = options[:local_context]
        defined = options.fetch(:defined, {})

        # If local context is not null, it contains a key that equals value, and the value associated with the key that equals value in defined is not true, then invoke the Create Term Definition subalgorithm, passing active context, local context, value as term, and defined. This will ensure that a term definition is created for value in active context during Context Processing.
        if local_context && local_context.has_key?(value) && !defined[value]
          depth {create_term_definition(local_context, value, defined)}
        end

        # If vocab is true and the active context has a term definition for value, return the associated IRI mapping.
        if options[:vocab] && (v_td = term_definitions[value])
          debug("expand_iri") {"match: #{value.inspect} to #{v_td.id}"} unless options[:quiet]
          return v_td.id
        end

        # If value contains a colon (:), it is either an absolute IRI or a compact IRI:
        if value.include?(':')
          prefix, suffix = value.split(':', 2)
          debug("expand_iri") {"prefix: #{prefix.inspect}, suffix: #{suffix.inspect}, vocab: #{vocab.inspect}"} unless options[:quiet]

          # If prefix is underscore (_) or suffix begins with double-forward-slash (//), return value as it is already an absolute IRI or a blank node identifier.
          return RDF::Node.new(namer.get_sym(suffix)) if prefix == '_'
          return RDF::URI(value) if suffix[0,2] == '//'

          # If local context is not null, it contains a key that equals prefix, and the value associated with the key that equals prefix in defined is not true, invoke the Create Term Definition algorithm, passing active context, local context, prefix as term, and defined. This will ensure that a term definition is created for prefix in active context during Context Processing.
          if local_context && local_context.has_key?(prefix) && !defined[prefix]
            create_term_definition(local_context, prefix, defined)
          end

          # If active context contains a term definition for prefix, return the result of concatenating the IRI mapping associated with prefix and suffix.
          result = if (td = term_definitions[prefix])
            result = td.id + suffix
          else
            # (Otherwise) Return value as it is already an absolute IRI.
            RDF::URI(value)
          end

          debug("expand_iri") {"result: #{result.inspect}"} unless options[:quiet]
          return result
        end
        debug("expand_iri") {"result: #{result.inspect}"} unless options[:quiet]

        result = if options[:vocab] && vocab
          # If vocab is true, and active context has a vocabulary mapping, return the result of concatenating the vocabulary mapping with value.
          vocab + value
        elsif options[:documentRelative] && base = options.fetch(:base, self.base)
          # Otherwise, if document relative is true, set value to the result of resolving value against the base IRI. Only the basic algorithm in section 5.2 of [RFC3986] is used; neither Syntax-Based Normalization nor Scheme-Based Normalization are performed. Characters additionally allowed in IRI references are treated in the same way that unreserved characters are treated in URI references, per section 6.5 of [RFC3987].
          RDF::URI(base).join(value).to_s
        elsif local_context && RDF::URI(value).relative?
          # If local context is not null and value is not an absolute IRI, an invalid IRI mapping error has been detected and processing is aborted.
          raise JSON::LD::InvalidContext::InvalidIRIMapping, "not an absolute IRI: #{value}"
        else
          RDF::URI(value)
        end
        debug(" =>") {result} unless options[:quiet]
        result
      end
    end

    ##
    # Compacts an absolute IRI to the shortest matching term or compact IRI
    #
    # @param [RDF::URI] iri
    # @param  [Hash{Symbol => Object}] options ({})
    # @option options [Object] :value
    #   Value, used to select among various maps for the same IRI
    # @option options [Boolean] :vocab
    #   specifies whether the passed iri should be compacted using the active context's vocabulary mapping
    # @option options [Boolean] :reverse
    #   specifies whether a reverse property is being compacted 
    #
    # @return [String] compacted form of IRI
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-compaction
    def compact_iri(iri, options = {})
      return if iri.nil?
      iri = iri.to_s
      depth(options) do
        debug {"compact_iri(#{iri.inspect}, #{options.inspect})"}

        value = options.fetch(:value, nil)

        if options[:vocab] && inverse_context.has_key?(iri)
          debug("compact_iri", "vocab and key in inverse context")
          default_language = self.default_language || @none
          containers = []
          tl, tl_value = "@language", "@null"
          containers << '@index' if index?(value)
          if options[:reverse]
            tl, tl_value = "@type", "@reverse"
            containers << '@set'
          elsif list?(value)
            debug("compact_iri", "list(#{value.inspect})")
            # if value is a list object, then set type/language and type/language value to the most specific values that work for all items in the list as follows:
            containers << "@list" unless index?(value)
            list = value['@list']
            common_type = nil
            common_language = default_language if list.empty?
            list.each do |item|
              item_language, item_type = "@none", "@none"
              if value?(item)
                if item.has_key?('@language')
                  item_language = item['@language']
                elsif item.has_key?('@type')
                  item_type = item['@type']
                else
                  item_language = "@null"
                end
              else
                item_type = '@id'
              end
              common_language ||= item_language
              if item_language != common_language && value?(item)
                debug("--") {"#{item_language} conflicts with #{common_language}, use @none"}
                common_language = '@none'
              end
              common_type ||= item_type
              if item_type != common_type
                common_type = '@none'
                debug("compact_iri") {"#{item_type} conflicts with #{common_type}, use @none"}
              end
            end

            common_language ||= '@none'
            common_type ||= '@none'
            debug("compact_iri", "common type: #{common_type}, common language: #{common_language}")
            if common_type != '@none'
              tl, tl_value = '@type', common_type
            else
              tl_value = common_language
            end
            debug("compact_iri", "list: containers: #{containers.inspect}, type/language: #{tl.inspect}, type/language value: #{tl_value.inspect}")
          else
            if value?(value)
              if value.has_key?('@language') && !index?(value)
                tl_value = value['@language']
                containers << '@language'
              elsif value.has_key?('@type')
                tl_value = '@id'
              end
              containers << '@set'
            end
            debug("compact_iri", "value: containers: #{containers.inspect}, type/language: #{tl.inspect}, type/language value: #{tl_value.inspect}")
          end

          containers << '@none'
          tl_value ||= '@null'
          preferred_values = []
          preferred_values << '@reverse' if tl_value == '@reverse'
          if %w(@id @reverse).include?(tl_value) && value.has_key?('@id')
            t_iri = compact_iri(value['@id'], :vocab => true, :document_relative => true)
            if (r_td = term_definitions[t_iri]) && r_td.id == value['@id']
              preferred_values.concat(%w(@vocab @id @none))
            else
              preferred_values.concat(%w(@id @vocab @none))
            end
          else
            preferred_values.concat([tl_value, '@none'])
          end
          debug("compact_iri", "preferred_values: #{preferred_values.inspect}")
          if p_term = select_term(iri, containers, tl, preferred_values)
            debug("=>") {"term: #{p_term.inspect}"}
            return p_term
          end
        end

        # At this point, there is no simple term that iri can be compacted to. If vocab is true and active context has a vocabulary mapping:
        if iri.start_with?(vocab) && iri.length > vocab.length
          suffix = iri[vocab.length..-1]
          debug("=>") {"vocab suffix: #{suffix.inspect}"}
          return suffix unless term_definitions.has_key?(suffix)
        end

        # The iri could not be compacted using the active context's vocabulary mapping. Try to create a compact IRI, starting by initializing compact IRI to null. This variable will be used to tore the created compact IRI, if any.
        candidates = []

        term_definitions.each do |term, td|
          next if term.include?(":")
          next if td.nil? || td.id == iri || !iri.start_with?(td.id)
          suffix = iri[td.id.length..-1]
          candidates << "#{term}:#{suffix}"
        end

        if !candidates.empty?
          debug("=>") {"compact iri: #{candidates.term_sort.first.inspect}"}
          return candidates.term_sort.first
        end

        # If we still don't have any terms and we're using standard_prefixes,
        # try those, and add to mapping
        if @options[:standard_prefixes]
          candidates = RDF::Vocabulary.
            select {|v| iri.start_with?(v.to_uri.to_s)}.
            map do |v|
              prefix = v.__name__.to_s.split('::').last.downcase
              set_mapping(prefix, v.to_uri.to_s)
              iri.sub(v.to_uri.to_s, "#{prefix}:").sub(/:$/, '')
            end

          if !candidates.empty?
            debug("=>") {"standard prefies: #{candidates.term_sort.first.inspect}"}
            return candidates.term_sort.first
          end
        end

        if !options[:vocab] && iri.start_with?(base.to_s)
          # transform iri to a relative IRI using the document's base IRI
          iri = iri[base.to_s.length..-1]
          debug("=>") {"relative iri: #{iri.inspect}"}
          return iri
        else
          debug("=>") {"absolute iri: #{iri.inspect}"}
          return iri
        end
      end
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
    # @param  [Hash{Symbol => Object}] options
    # @option options [Boolean] :useNativeTypes (true) use native representations
    #
    # @return [Hash] Object representation of value
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-expansion
    def expand_value(property, value, options = {})
      options = {:useNativeTypes => true}.merge(options)
      depth(options) do
        debug("expand_value") {"property: #{property.inspect}, value: #{value.inspect}"}

        # If the active property has a type mapping in active context that is @id, return a new JSON object containing a single key-value pair where the key is @id and the value is the result of using the IRI Expansion algorithm, passing active context, value, and true for document relative.
        if (td = term_definitions.fetch(property, TermDefinition.new)) && td.type_mapping == '@id'
          debug("expand_value") {"as relative IRI: #{value.inspect}"}
          return {'@id' => expand_iri(value, :documentRelative => true).to_s}
        end

        # If active property has a type mapping in active context that is @vocab, return a new JSON object containing a single key-value pair where the key is @id and the value is the result of using the IRI Expansion algorithm, passing active context, value, true for vocab, and true for document relative.
        if td.type_mapping == '@vocab'
          debug("expand_value") {"as vocab IRI: #{value.inspect}"}
          return {'@id' => expand_iri(value, :vocab => true, :documentRelative => true).to_s}
        end

        value = RDF::Literal(value) if
          value.is_a?(Date) ||
          value.is_a?(DateTime) ||
          value.is_a?(Time)

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
        else
          # Otherwise, initialize result to a JSON object with an @value member whose value is set to value.
          res = {'@value' => value}

          if td.type_mapping
            res['@type'] = td.type_mapping.to_s
          elsif value.is_a?(String)
            if td.language_mapping
              res['@language'] = td.language_mapping
            elsif default_language && td.language_mapping.nil?
              res['@language'] = default_language
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
        when value['@type'] && expand_iri(value['@type'], :vocab => true) == coerce(property)
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
      v << "vocab=#{vocab}" if vocab
      v << "def_language=#{default_language}" if default_language
      v << "term_definitions[#{term_definitions.length}]=#{term_definitions}"
      v.join(" ") + "]"
    end
    
    def dup
      # Also duplicate mappings, coerce and list
      that = self
      ec = super
      ec.instance_eval do
        @term_definitions = that.term_definitions.dup
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
      @provided_context = nil
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
    # Inverse Context creation
    #
    # When there is more than one term that could be chosen to compact an IRI, it has to be ensured that the term selection is both deterministic and represents the most context-appropriate choice whilst taking into consideration algorithmic complexity.
    #
    # In order to make term selections, the concept of an inverse context is introduced. An inverse context is essentially a reverse lookup table that maps container mappings, type mappings, and language mappings to a simple term for a given active context. A inverse context only needs to be generated for an active context if it is being used for compaction.
    #
    # To make use of an inverse context, a list of preferred container mappings and the type mapping or language mapping are gathered for a particular value associated with an IRI. These parameters are then fed to the Term Selection algorithm, which will find the term that most appropriately matches the value's mappings.
    #
    # @return [Hash{String => Hash{String => String}}]
    def inverse_context
      @inverse_context ||= begin
        result = {}
        default_language = self.default_language || '@none'
        term_definitions.keys.sort do |a, b|
          a.length == b.length ? (a <=> b) : (a.length <=> b.length)
        end.each do |term|
          next unless td = term_definitions[term]
          container = td.container_mapping || '@none'
          container_map = result[td.id.to_s] ||= {}
          tl_map = container_map[container] ||= {'@language' => {}, '@type' => {}}
          type_map = tl_map['@type']
          language_map = tl_map['@language']
          if td.reverse_property
            type_map['@reverse'] ||= term
          elsif td.type_mapping
            type_map[td.type_mapping.to_s] ||= term
          elsif !td.language_mapping.nil?
            language = td.language_mapping || '@null'
            language_map[language] ||= term
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
      debug("select_term") {
        "iri: #{iri.inspect}, " +
        "containers: #{containers.inspect}, " +
        "type_language: #{type_language.inspect}, " +
        "preferred_values: #{preferred_values.inspect}"
      }
      container_map = inverse_context[iri]
      debug("  ") {"container_map: #{container_map.inspect}"}
      containers.each do |container|
        next unless container_map.has_key?(container)
        tl_map = container_map[container]
        value_map = tl_map[type_language]
        preferred_values.each do |item|
          next unless value_map.has_key?(item)
          debug("=>") {value_map[item].inspect}
          return value_map[item]
        end
      end
      debug("=>") {"nil"}
      nil
    end
  end
end
