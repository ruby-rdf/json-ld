require 'open-uri'
require 'json'
require 'bigdecimal'

module JSON::LD
  class EvaluationContext # :nodoc:
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
    
    # Default language
    #
    # This adds a language to plain strings that aren't otherwise coerced
    # @attr [String]
    attr :language, true
    
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
      @base = RDF::URI(options[:base_uri]) if options[:base_uri]
      @mappings =  {}
      @coercions = {}
      @containers = {}
      @iri_to_curie = {}
      @iri_to_term = {
        RDF.to_uri.to_s => "rdf",
        RDF::XSD.to_uri.to_s => "xsd"
      }

      @options = options

      # Load any defined prefixes
      (options[:prefixes] || {}).each_pair do |k, v|
        @iri_to_term[v] = k
      end

      debug("init") {"iri_to_term: #{iri_to_term.inspect}"}
      
      yield(self) if block_given?
    end

    # Create an Evaluation Context using an existing context as a start by parsing the input.
    #
    # @param [IO, Array, Hash, String] input
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
        
        num_updates = 1
        while num_updates > 0 do
          num_updates = 0

          # Map terms to IRIs/keywords first
          context.each do |key, value|
            # Expand a string value, unless it matches a keyword
            debug("parse") {"Hash[#{key}] = #{value.inspect}"}
            if (new_ec.mapping(key) || key) == '@language'
              new_ec.language = value.to_s unless value.to_s == '@language' # due to aliasing
            elsif term_valid?(key)
              # Extract IRI mapping. This is complicated, as @id may have been aliased
              if value.is_a?(Hash)
                id_key = value.keys.detect {|k| new_ec.mapping(k) == '@id'} || '@id'
                value = value[id_key]
              end
              raise InvalidContext::Syntax, "unknown mapping for #{key.inspect} to #{value.class}" unless value.is_a?(String) || value.nil?

              iri = new_ec.expand_iri(value, :position => :predicate) if value.is_a?(String)
              if iri && new_ec.mappings[key] != iri
                # Record term definition
                new_ec.set_mapping(key, iri)
                num_updates += 1
              end
            elsif !new_ec.expand_iri(key).is_a?(RDF::URI)
              raise InvalidContext::Syntax, "key #{key.inspect} is invalid"
            end
          end
        end

        # Next, look for coercion using new_ec
        context.each do |key, value|
          # Expand a string value, unless it matches a keyword
          debug("parse") {"coercion/list: Hash[#{key}] = #{value.inspect}"}
          prop = new_ec.expand_iri(key, :position => :predicate).to_s
          case value
          when Hash
            # Must have one of @id, @type or @container
            expanded_keys = value.keys.map {|k| new_ec.mapping(k) || k}
            raise InvalidContext::Syntax, "mapping for #{key.inspect} missing one of @id, @type or @container" if (%w(@id @type @container) & expanded_keys).empty?
            value.each do |key2, value2|
              expanded_key = new_ec.mapping(key2) || key2
              iri = new_ec.expand_iri(value2, :position => :predicate) if value2.is_a?(String)
              case expanded_key
              when '@type'
                raise InvalidContext::Syntax, "unknown mapping for '@type' to #{value2.class}" unless value2.is_a?(String) || value2.nil?
                if new_ec.coerce(key) != iri
                  raise InvalidContext::Syntax, "unknown mapping for '@type' to #{iri.inspect}" unless RDF::URI(iri).absolute? || iri == '@id'
                  # Record term coercion
                  debug("parse") {"coerce #{key.inspect} to #{iri.inspect}"}
                  new_ec.coerce(key, iri)
                end
              when '@container'
                raise InvalidContext::Syntax, "unknown mapping for '@container' to #{value2.class}" unless %w(@list @set).include?(value2)
                if new_ec.container(key) != value2
                  debug("parse") {"container #{key.inspect} as #{value2.inspect}"}
                  new_ec.container(key, value2)
                end
              end
            end
          when String
            # handled in previous loop
          when nil
            case prop
            when '@language'
              # Remove language mapping from active context
              new_ec.language = nil
            else
              new_ec.set_mapping(prop, nil)
            end
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
          ctx[self.alias('@language')] = language.to_s if language

          # Mappings
          mappings.keys.sort.each do |k|
            next unless term_valid?(k.to_s)
            debug {"=> mappings[#{k}] => #{mappings[k]}"}
            ctx[k] = mappings[k].to_s
          end

          unless coercions.empty? && containers.empty?
            # Coerce
            (coercions.keys + containers.keys).uniq.sort.each do |k|
              next if [self.alias('@type'), RDF.type.to_s].include?(k.to_s)

              # Turn into long form
              ctx[k] ||= Hash.ordered
              if ctx[k].is_a?(String)
                defn = Hash.ordered
                defn[self.alias("@id")] = ctx[k]
                ctx[k] = defn
              end

              debug {"=> coerce(#{k}) => #{coerce(k)}"}
              if coerce(k) && !NATIVE_DATATYPES.include?(coerce(k))
                # If coercion doesn't depend on any prefix definitions, it can be folded into the first context block
                dt = compact_iri(coerce(k), :position => :datatype, :depth => @depth)
                # Fold into existing definition
                ctx[k][self.alias("@type")] = dt
                debug {"=> reuse datatype[#{k}] => #{dt}"}
              end

              debug {"=> container(#{k}) => #{container(k)}"}
              if container(k) == '@list'
                # It is not dependent on previously defined terms, fold into existing definition
                ctx[k][self.alias("@container")] = self.alias('@list')
                debug {"=> reuse list_range[#{k}] => #{self.alias('@list')}"}
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
#      raise "mapping term #{term.inspect} must be a string" unless term.is_a?(String)
#      raise "mapping value #{value.inspect} must be an RDF::URI" unless value.nil? || value.to_s[0,1] == '@' || value.is_a?(RDF::URI)
      debug {"map #{term.inspect} to #{value}"} unless @mappings[term] == value
      iri_to_term.delete(@mappings[term]) if @mappings[term]
      if value
        @mappings[term] = value
        iri_to_term[value] = term
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
      @mappings.invert.fetch(value, value)
    end
    
    ##
    # Set term coercion
    #
    # @param [String] property in unexpanded form
    # @param [RDF::URI, '@id'] value (nil)
    #
    # @return [RDF::URI, '@id']
    def coerce(property, value = nil)
      # Map property, if it's not an RDF::Value
      return '@id' if [RDF.type, '@type'].include?(property)  # '@type' always is an IRI
      if value
        debug {"coerce #{property.inspect} to #{value}"} unless @coercions[property.to_s] == value
        @coercions[property] = value
      elsif type = @coercions.fetch(property, nil)
        debug("coerce") {"#{property.inspect} coerced to #{type}"}
        type
      else
        nil
      end
    end

    ##
    # Retrieve container mapping, add it if `value` is provided
    #
    # @param [String] property in unexpanded form
    # @param [Boolean] value (nil)
    # @return [String]
    def container(property, value = nil)
      unless value.nil?
        debug {"coerce #{property.inspect} to @list"} unless @containers[property.to_s] == value
        @containers[property.to_s] = value
      end
      @containers[property.to_s]
    end

    ##
    # Retrieve container mapping, add it if `value` is provided
    #
    # @param [String] property in full IRI string representation
    # @param [String] value one of @list, @set or nil
    # @return [Boolean]
    def set_container(property, value)
      return if @containers[property.to_s] == value
      debug {"coerce #{property.inspect} to #{value.inspect}"} 
      @containers[property.to_s] = value
    end

    ##
    # Determine if `term` is a suitable term.
    # Basically, a keyword (other than @context), an NCName or an absolute IRI
    #
    # @param [String] term
    # @return [Boolean]
    def term_valid?(term)
      term.empty? ||
      term.match(NC_REGEXP) ||
      term.match(/^[a-zA-Z][a-zA-Z0-9\+\-\.]*:.*$/) || # This is pretty permissive
      (term.match(/^@\w+/) && term != '@context')
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
      prefix, suffix = iri.split(":", 2)
      debug("expand_iri") {"prefix: #{prefix.inspect}, suffix: #{suffix.inspect}"} unless options[:quiet]
      prefix = prefix.to_s
      case
      when prefix == '_'              then bnode(suffix)
      when iri.to_s[0,1] == "@"       then iri
      when iri =~ %r(://)             then uri(iri)
      when mappings.has_key?(prefix)  then uri(mappings[prefix] + suffix.to_s)
      when base                       then base.join(iri)
      else                                 uri(iri)
      end
    end

    ##
    # Compact an IRI
    #
    # @param [RDF::URI] iri
    # @param  [Hash{Symbol => Object}] options ({})
    # @option options [:subject, :predicate, :object, :datatype] position
    #   Useful when determining how to serialize.
    #
    # @return [String] compacted form of IRI
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-compaction
    def compact_iri(iri, options = {})
      return iri.to_s if [RDF.first, RDF.rest, RDF.nil].include?(iri)  # Don't cause these to be compacted

      depth(options) do
        debug {"compact_iri(#{iri.inspect}, #{options.inspect})"}

        result = self.alias('@type') if options[:position] == :predicate && iri == RDF.type
        result ||= @mappings.invert.fetch(iri, nil) # Like alias, but only if there is a mapping
        result ||= get_term_or_curie(iri)
        result ||= iri.to_s

        debug {"=> #{result.inspect}"}
        result
      end
    end

    ##
    # Expand a value from compacted to expanded form making the context
    # unnecessary. This method is used as part of more general expansion
    # and operates on RHS values, using a supplied key to determine @type and @list
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
            language ? {"@value" => value.to_s, "@language" => language.to_s} : value.to_s
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
      raise ProcessingError::Lossy, "attempt to compact a non-object value" unless value.is_a?(Hash)

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
        when %(@id @type).include?(property) && value.has_key?('@id')
          # Compact @id representation for @id or @type
          debug {" (@id & @id|@type)"}
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
        when value['@language'] && value['@language'] == language
          # Compact language
          debug {" (@language) == #{language}"}
          value['@value']
        when value['@value'] && !value['@language'] && !value['@type'] && !coerce(property) && !language
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
      ec.language = language
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
    # Return a CURIE for the IRI, or nil. Adds namespace of CURIE to defined prefixes
    # @param [RDF::Resource] resource
    # @return [String, nil] value to use to identify IRI
    def get_term_or_curie(resource)
      debug {"get_term_or_curie(#{resource.inspect})"}
      case resource
      when RDF::Node, /^_:/
        return resource.to_s
      when String
        iri = resource
        resource = RDF::URI(resource)
        return nil unless resource.absolute?
      when RDF::URI
        iri = resource.to_s
        return iri if options[:expand]
      else
        return nil
      end

      curie = case
      when iri_to_curie.has_key?(iri)
        return iri_to_curie[iri]
      when u = iri_to_term.keys.detect {|i| iri.index(i.to_s) == 0}
        # Use a defined prefix
        prefix = iri_to_term[u]
        set_mapping(prefix, u)
        iri.sub(u.to_s, "#{prefix}:").sub(/:$/, '')
      when @options[:standard_prefixes] && vocab = RDF::Vocabulary.detect {|v| iri.index(v.to_uri.to_s) == 0}
        prefix = vocab.__name__.to_s.split('::').last.downcase
        set_mapping(prefix, vocab.to_uri.to_s)
        iri.sub(vocab.to_uri.to_s, "#{prefix}:").sub(/:$/, '')
      else
        debug "no mapping found for #{iri} in #{iri_to_term.inspect}"
        nil
      end
      
      iri_to_curie[iri] = curie
    rescue Addressable::URI::InvalidURIError => e
      raise RDF::WriterError, "Invalid IRI #{resource.inspect}: #{e.message}"
    end

    # Add debug event to debug array, if specified
    #
    # @param [String] message
    # @yieldreturn [String] appended to message, to allow for lazy-evaulation of message
    def debug(*args)
      return unless ::JSON::LD.debug? || @options[:debug]
      list = args
      list << yield if block_given?
      message = " " * (@depth || 0) * 2 + (list.empty? ? "" : list.join(": "))
      puts message if JSON::LD::debug?
      @options[:debug] << message if @options[:debug].is_a?(Array)
    end

    # Increase depth around a method invocation
    def depth(options = {})
      old_depth = @depth || 0
      @depth = (options[:depth] || old_depth) + 1
      ret = yield
      @depth = old_depth
      ret
    end
  end
end