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
    # The @list keyword is used to specify that properties having an array value are to be treated
    # as an ordered list, rather than a normal unordered list
    # @attr [Hash{String => true}]
    attr :lists, true
    
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
      @lists = {}
      @iri_to_curie = {}
      @iri_to_term = {
        RDF.to_uri.to_s => "rdf",
        RDF::XSD.to_uri.to_s => "xsd"
      }

      @options = options

      # Load any defined prefixes
      (options[:prefixes] || {}).each_pair do |k, v|
        @iri_to_term[v.to_s] = k
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
          open(context.to_s) {|f| ec = parse(f)}
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
        debug("parse") {"=> provided_context: #{context.inspect}"}
        
        num_updates = 1
        while num_updates > 0 do
          num_updates = 0

          # Map terms to IRIs first
          context.each do |key, value|
            # Expand a string value, unless it matches a keyword
            debug("parse") {"Hash[#{key}] = #{value.inspect}"}
            if key == '@language'
              new_ec.language = value.to_s
            elsif term_valid?(key)
              # Extract IRI mapping
              value = value['@id'] if value.is_a?(Hash)
              raise InvalidContext::Syntax, "unknown mapping for #{key.inspect} to #{value.class}" unless value.is_a?(String) || value.nil?

              iri = new_ec.expand_iri(value, :position => :predicate) if value.is_a?(String)
              if iri && new_ec.mappings[key] != iri
                # Record term definition
                new_ec.mapping(key, iri)
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
            # Must have one of @id, @type or @list
            raise InvalidContext::Syntax, "mapping for #{key.inspect} missing one of @id, @type or @list" if (%w(@id @type @list) & value.keys).empty?
            raise InvalidContext::Syntax, "unknown mappings for #{key.inspect}: #{value.keys.inspect}" unless (value.keys - %w(@id @type @list)).empty?
            value.each do |key2, value2|
              iri = new_ec.expand_iri(value2, :position => :predicate) if value2.is_a?(String)
              case key2
              when '@type'
                raise InvalidContext::Syntax, "unknown mapping for '@type' to #{value2.class}" unless value2.is_a?(String) || value2.nil?
                if new_ec.coerce(prop) != iri
                  raise InvalidContext::Syntax, "unknown mapping for '@type' to #{iri.inspect}" unless RDF::URI(iri).absolute? || iri == '@id'
                  # Record term coercion
                  debug("parse") {"coerce #{prop.inspect} to #{iri.inspect}"}
                  new_ec.coerce(prop, iri)
                end
              when '@list'
                raise InvalidContext::Syntax, "unknown mapping for '@list' to #{value2.class}" unless value2.is_a?(TrueClass) || value2.is_a?(FalseClass)
                if new_ec.list(prop) != value2
                  debug("parse") {"list #{prop.inspect} as #{value2.inspect}"}
                  new_ec.list(prop, value2)
                end
              end
            end
          when String
            # handled in previous loop
          else
            raise InvalidContext::Syntax, "attemp to map #{key.inspect} to #{value.class}"
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
          ctx = Hash.new
          ctx['@language'] = language.to_s if language

          # Prefixes
          mappings.keys.sort {|a,b| a.to_s <=> b.to_s}.each do |k|
            next unless term_valid?(k.to_s)
            debug {"=> mappings[#{k}] => #{mappings[k]}"}
            ctx[k.to_s] = mappings[k].to_s
          end

          unless coercions.empty? && lists.empty?
            # Coerce
            (coercions.keys + lists.keys).uniq.sort.each do |k|
              next if ['@type', RDF.type.to_s].include?(k.to_s)

              k_iri = compact_iri(k, :position => :predicate, :depth => @depth).to_s
              k_prefix = k_iri.split(':').first

              # Turn into long form
              ctx[k_iri] ||= Hash.new
              if ctx[k_iri].is_a?(String)
                defn = Hash.new
                defn["@id"] = ctx[k_iri]
                ctx[k_iri] = defn
              end

              debug {"=> coerce(#{k}) => #{coerce(k)}"}
              if coerce(k) && !NATIVE_DATATYPES.include?(coerce(k))
                # If coercion doesn't depend on any prefix definitions, it can be folded into the first context block
                dt = compact_iri(coerce(k), :position => :datatype, :depth => @depth)
                # Fold into existing definition
                ctx[k_iri]["@type"] = dt
                debug {"=> reuse datatype[#{k_iri}] => #{dt}"}
              end

              debug {"=> list(#{k}) => #{list(k)}"}
              if list(k)
                # It is not dependent on previously defined terms, fold into existing definition
                ctx[k_iri]["@list"] = true
                debug {"=> reuse list_range[#{k_iri}] => true"}
              end
              
              # Remove an empty definition
              ctx.delete(k_iri) if ctx[k_iri].empty?
            end
          end

          debug {"start_doc: context=#{ctx.inspect}"}
          ctx
        end

        # Return hash with @context, or empty
        r = Hash.new
        r['@context'] = use_context unless use_context.nil? || use_context.empty?
        r
      end
    end
    
    ##
    # Retrieve term mapping, add it if `value` is provided
    #
    # @param [String, #to_s] term
    # @param [RDF::URI, String] value (nil)
    #
    # @return [RDF::URI, String]
    def mapping(term, value = nil)
      if value
        debug {"map #{term.inspect} to #{value}"} unless @mappings[term.to_s] == value
        @mappings[term.to_s] = value
        iri_to_term[value.to_s] = term
      end
      @mappings.has_key?(term.to_s) && @mappings[term.to_s]
    end

    ##
    # Retrieve term coercion, add it if `value` is provided
    #
    # @param [String] property in full IRI string representation
    # @param [RDF::URI, '@id'] value (nil)
    #
    # @return [RDF::URI, '@id']
    def coerce(property, value = nil)
      return '@id' if [RDF.type, '@type'].include?(property)  # '@type' always is an IRI
      if value
        debug {"coerce #{property.inspect} to #{value}"} unless @coercions[property.to_s] == value
        @coercions[property.to_s] = value
      end
      @coercions[property.to_s] if @coercions.has_key?(property.to_s)
    end

    ##
    # Retrieve list mapping, add it if `value` is provided
    #
    # @param [String] property in full IRI string representation
    # @param [Boolean] value (nil)
    # @return [Boolean]
    def list(property, value = nil)
      unless value.nil?
        debug {"coerce #{property.inspect} to @list"} unless @lists[property.to_s] == value
        @lists[property.to_s] = value
      end
      @lists[property.to_s] && @lists[property.to_s]
    end

    ##
    # Determine if `term` is a suitable term
    #
    # @param [String] term
    # @return [Boolean]
    def term_valid?(term)
      term.empty? || term.match(NC_REGEXP)
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
      debug("expand_iri") {"prefix: #{prefix.inspect}, suffix: #{suffix.inspect}"}
      prefix = prefix.to_s
      case
      when prefix == '_'              then bnode(suffix)
      when iri.to_s[0,1] == "@"       then iri
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
        debug {"compact_iri(#{options.inspect}, #{iri.inspect})"}

        result = '@type' if options[:position] == :predicate && iri == RDF.type
        result ||= get_curie(iri) || iri.to_s

        debug {"=> #{result.inspect}"}
        result
      end
    end

    ##
    # Expand a value from compacted to expanded form making the context
    # unnecessary. This method is used as part of more general expansion
    # and operates on RHS values, using a supplied key to determine
    # @type and @list coercion rules.
    #
    # @param [RDF::URI] predicate
    #   Associated predicate used to find coercion rules
    # @param [Hash, String] value
    #   Value (literal or IRI) to be expanded
    # @param  [Hash{Symbol => Object}] options
    #
    # @return [Hash] Object representation of value
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-expansion
    def expand_value(predicate, value, options = {})
      depth(options) do
        debug("expand_value") {"predicate: #{predicate}, value: #{value.inspect}, coerce: #{coerce(predicate).inspect}"}
        result = case value
        when TrueClass, FalseClass, RDF::Literal::Boolean
          {"@literal" => value.to_s, "@type" => RDF::XSD.boolean.to_s}
        when Integer, RDF::Literal::Integer
          {"@literal" => value.to_s, "@type" => RDF::XSD.integer.to_s}
        when BigDecimal, RDF::Literal::Decimal
          {"@literal" => value.to_s, "@type" => RDF::XSD.decimal.to_s}
        when Float, RDF::Literal::Double
          {"@literal" => value.to_s, "@type" => RDF::XSD.double.to_s}
        when Date, Time, DateTime
          l = RDF::Literal(value)
          {"@literal" => l.to_s, "@type" => l.datatype.to_s}
        when RDF::URI
          {'@id' => value.to_s}
        when RDF::Literal
          res = Hash.new
          res['@literal'] = value.to_s
          res['@type'] = value.datatype.to_s if value.has_datatype?
          res['@language'] = value.language.to_s if value.has_language?
          res
        else
          case coerce(predicate)
          when '@id'
            {'@id' => expand_iri(value, :position => :object).to_s}
          when nil
            language ? {"@literal" => value.to_s, "@language" => language.to_s} : value.to_s
          else
            res = Hash.new
            res['@literal'] = value.to_s
            res['@type'] = coerce(predicate).to_s
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
    # @param [RDF::URI] predicate
    #   Associated predicate used to find coercion rules
    # @param [Hash] value
    #   Value (literal or IRI), in full object representation, to be compacted
    # @param  [Hash{Symbol => Object}] options
    #
    # @return [Hash] Object representation of value
    # @raise [ProcessingError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-compaction
    def compact_value(predicate, value, options = {})
      raise ProcessingError::Lossy, "attempt to compact a non-object value" unless value.is_a?(Hash)

      depth(options) do
        debug("compact_value") {"predicate: #{predicate.inspect}, value: #{value.inspect}, coerce: #{coerce(predicate).inspect}"}

        result = case
        when %w(boolean integer double).any? {|t| expand_iri(value['@type'], :position => :datatype) == RDF::XSD[t]}
          # Compact native type
          debug {" (native)"}
          l = RDF::Literal(value['@literal'], :datatype => expand_iri(value['@type'], :position => :datatype))
          l.canonicalize.object
        when coerce(predicate) == '@id' && value.has_key?('@id')
          # Compact an @id coercion
          debug {" (@id & coerce)"}
          compact_iri(value['@id'], :position => :object)
        when value['@type'] && expand_iri(value['@type'], :position => :datatype) == coerce(predicate)
          # Compact common datatype
          debug {" (@type & coerce) == #{coerce(predicate)}"}
          value['@literal']
        when value.has_key?('@id')
          # Compact an IRI
          value['@id'] = compact_iri(value['@id'], :position => :object)
          debug {" (@id => #{value['@id']})"}
          value
        when value['@language'] && value['@language'] == language
          # Compact language
          debug {" (@language) == #{language}"}
          value['@literal']
        when value['@literal'] && !value['@language'] && !value['@type'] && !coerce(predicate) && !language
          # Compact simple literal to string
          debug {" (@literal && !@language && !@type && !coerce && !language)"}
          value['@literal']
        when value['@type']
          # Compact datatype
          debug {" (@type)"}
          value['@type'] = compact_iri(value['@type'], :position => :datatype)
          value
        else
          # Otherwise, use original value
          debug {" (no change)"}
          value
        end
        
        debug {"=> #{result.inspect}"}
        result
      end
    end

    def inspect
      v = %w([EvaluationContext)
      v << "mappings[#{mappings.keys.length}]=#{mappings}"
      v << "coercions[#{coercions.keys.length}]=#{coercions}"
      v << "lists[#{lists.length}]=#{lists}"
      v.join(", ") + "]"
    end
    
    def dup
      # Also duplicate mappings, coerce and list
      ec = super
      ec.mappings = mappings.dup
      ec.coercions = coercions.dup
      ec.lists = lists.dup
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
    def get_curie(resource)
      debug {"get_curie(#{resource.inspect})"}
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
        mapping(prefix, u)
        iri.sub(u.to_s, "#{prefix}:").sub(/:$/, '')
      when @options[:standard_prefixes] && vocab = RDF::Vocabulary.detect {|v| iri.index(v.to_uri.to_s) == 0}
        prefix = vocab.__name__.to_s.split('::').last.downcase
        mapping(prefix, vocab.to_uri.to_s)
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