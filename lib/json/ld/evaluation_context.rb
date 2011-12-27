require 'open-uri'
require 'json'
require 'bigdecimal'

module JSON::LD
  class EvaluationContext # :nodoc:
    # The base.
    #
    # The `@base` string is a special keyword that states that any relative IRI MUST be appended to the string
    # specified by `@base`.
    #
    # @attr [RDF::URI]
    attr :base, true

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

    # The default vocabulary
    #
    # A value to use as the prefix URI when a term is used.
    # This specification does not define an initial setting for the default vocabulary.
    # Host Languages may define an initial setting.
    #
    # @attr [String]
    attr :vocab, true

    # Type coersion
    #
    # The @type keyword is used to specify type coersion rules for the data. For each key in the map, the
    # key is a String representation of the property for which String values will be coerced and
    # the value is the datatype (or @id) to coerce to. Type coersion for
    # the value `@id` asserts that all vocabulary terms listed should undergo coercion to an IRI,
    # including `@base` processing for relative IRIs and CURIE processing for compact IRI Expressions like
    # `foaf:homepage`.
    #
    # @attr [Hash{String => String}]
    attr :coerce, true

    # List coercion
    #
    # The @list keyword is used to specify that properties having an array value are to be treated
    # as an ordered list, rather than a normal unordered list
    # @attr [Hash{String => true}]
    attr :list, true
    
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
      @base = nil
      @mappings =  {}
      @vocab = nil
      @coerce = {}
      @list = {}
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
    # @raise [IOError]
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
          raise JSON::ParserError, "missing @context" unless ctx.is_a?(Hash) && ctx["@context"]
          parse(ctx["@context"])
        rescue JSON::ParserError => e
          debug("parse") {"Failed to parse @context from remote document at #{context}: #{e.message}"}
          raise JSON::ParserError, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when String
        debug("parse") {"remote: #{context}"}
        # Load context document, if it is a string
        ec = nil
        begin
          open(context.to_s) {|f| ec = parse(f)}
          ec.provided_context = context
          debug("parse") {"=> provided_context: #{context.inspect}"}
          ec
        rescue IOError => e
          debug("parse") {"Failed to retrieve @context from remote document at #{context}: #{e.message}"}
          raise IOError, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
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
        
        # Map terms to IRIs first
        context.each do |key, value|
          # Expand a string value, unless it matches a keyword
          value = expand_iri(value, :position => :predicate) if value.is_a?(String) && value[0,1] != '@'
          debug("parse") {"Hash[#{key}] = #{value.inspect}"}
          case key
          when '@vocab'    then new_ec.vocab = value.to_s
          when '@base'     then new_ec.base  = uri(value)
          when '@language' then new_ec.language = value.to_s
          else
            # If value is a Hash process contents
            value = value['@id'] if value.is_a?(Hash)
            iri = expand_iri(value || key, :position => :predicate) if term_valid?(key)

            # Record term definition
            new_ec.add_mapping(key, iri) if term_valid?(key)
          end
        end

        # Next, look for coercion using new_ec
        context.each do |key, value|
          # Expand a string value, unless it matches a keyword
          value = expand_iri(value, :position => :predicate) if value.is_a?(String) && value[0,1] != '@'
          debug("parse") {"Hash[#{key}] = #{value.inspect}"}
          case key
          when '@vocab'    then # done
          when '@base'     then # done
          when '@language' then # done
          else
            # If value is a Hash process contents
            case value
            when Hash
              prop = new_ec.expand_iri(key, :position => :predicate).to_s

              # List inclusion
              if value["@list"]
                new_ec.add_list(prop)
              end

              # Coercion
              case value["@type"]
              when "@id"
                # Must be of the form { "term" => { "@type" => "@id"}}
                debug("parse") {"@type @id"}
                new_ec.coerce[prop] = '@id'
              when String
                # Must be of the form { "term" => { "@type" => "xsd:string"}}
                dt = new_ec.expand_iri(value["@type"], :position => :predicate)
                debug("parse") {"@type #{dt}"}
                new_ec.coerce[prop] = dt
              end
            else
              # Given a string (or URI), us it
              new_ec.add_mapping(key, value)
            end
          end
        end

        debug("parse") {"iri_to_term: #{new_ec.iri_to_term.inspect}"}

        new_ec
      end
    end

    ##
    # Generate @context
    #
    # If a context was supplied in global options, use that, otherwise, generate one
    # from this representation.
    #
    # @return [Hash]
    def serialize(options)
      depth(options) do
        use_context = if provided_context
          debug "serlialize: reuse context: #{provided_context.inspect}"
          provided_context
        else
          debug("serlialize: generate context")
          debug {"=> context: #{inspect}"}
          ctx = Hash.new
          ctx['@base'] = base.to_s if base
          ctx['@vocab'] = vocab.to_s if vocab
          ctx['@language'] = language.to_s if language

          # Prefixes
          mappings.keys.sort {|a,b| a.to_s <=> b.to_s}.each do |k|
            next unless term_valid?(k.to_s)
            debug {"=> mappings[#{k}] => #{mappings[k]}"}
            ctx[k.to_s] = mappings[k].to_s
          end

          unless coerce.empty? && list.empty?
            ctx2 = Hash.new

            # Coerce
            (coerce.keys + list.keys).uniq.sort.each do |k|
              next if ['@type', RDF.type.to_s].include?(k.to_s)

              k_iri = compact_iri(k, :position => :predicate, :depth => @depth)
              k_prefix = k_iri.to_s.split(':').first

              if coerce[k] && !NATIVE_DATATYPES.include?(coerce[k])
                # If coercion doesn't depend on any prefix definitions, it can be folded into the first context block
                dt = compact_iri(coerce[k], :position => :datatype, :depth => @depth)
                dt_prefix = dt.split(':').first
                if ctx[dt_prefix] || (ctx[k_prefix] && k_prefix != k_iri.to_s)
                  # It uses a prefix defined above, place in new context block
                  ctx2[k_iri.to_s] = Hash.new
                  ctx2[k_iri.to_s]['@type'] = dt
                  debug {"=> new datatype[#{k_iri}] => #{dt}"}
                else
                  # It is not dependent on previously defined terms, fold into existing definition
                  ctx[k_iri] ||= Hash.new
                  if ctx[k_iri].is_a?(String)
                    defn = Hash.new
                    defn["@id"] = ctx[k_iri]
                    ctx[k_iri] = defn
                  end
                  ctx[k_iri]["@type"] = dt
                  debug {"=> reuse datatype[#{k_iri}] => #{dt}"}
                end
              end

              if list[k]
                if ctx2[k_iri.to_s] || (ctx[k_prefix] && k_prefix != k_iri.to_s)
                  # Place in second context block
                  ctx2[k_iri.to_s] ||= Hash.new
                  ctx2[k_iri.to_s]['@list'] = true
                  debug {"=> new list_range[#{k_iri}] => true"}
                else
                  # It is not dependent on previously defined terms, fold into existing definition
                  ctx[k_iri] ||= Hash.new
                  if ctx[k_iri].is_a?(String)
                    defn = Hash.new
                    defn["@id"] = ctx[k_iri]
                    ctx[k_iri] = defn
                  end
                  ctx[k_iri]["@list"] = true
                  debug {"=> reuse list_range[#{k_iri}] => true"}
                end
              end
            end

            # Separate contexts, so uses of prefixes are defined after the definitions of prefixes
            ctx = [ctx, ctx2].reject(&:empty?)
            ctx = ctx.first if ctx.length == 1
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
    # Add a term mapping
    #
    # @param [String] term
    # @param [String] value
    def add_mapping(term, value)
      debug {"map #{term.inspect} to #{value}"} unless mappings[term] == value
      mappings[term] = value
      iri_to_term[value.to_s] = term
    end

    ##
    # Add a list coercion
    #
    # @param [String] property in full IRI string representation
    def add_list(property)
      debug {"coerce #{property.inspect} to @list"} unless list[property]
      list[property] = true
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
    # Expand an IRI
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
      case
      when prefix == '_'
        bnode(suffix)
      when iri.to_s[0,1] == "@"
        iri
      when self.mappings.has_key?(prefix)
        uri(self.mappings[prefix] + suffix.to_s)
      when [:subject, :object].include?(options[:position]) && base
        base.join(iri)
      when options[:position] == :predicate && vocab
        t_uri = uri(iri)
        t_uri.absolute? ? t_uri : uri(vocab + iri)
      else
        uri(iri)
      end
    end

    ##
    # Compact an IRI
    #
    # @param [RDF::URI] iri
    # @param [String] base Base to apply to URIs
    # @param  [Hash{Symbol => Object}] options
    # @option options [:subject, :predicate, :object, :datatype] position
    #   Useful when determining how to serialize.
    #
    # @return [String] compacted form of IRI
    # @see http://json-ld.org/spec/latest/json-ld-api/#iri-compaction
    def compact_iri(iri, options)
      return iri.to_s if [RDF.first, RDF.rest, RDF.nil].include?(iri)  # Don't cause these to be compacted

      depth(options) do
        debug {"compact_iri(#{options.inspect}, #{iri.inspect})"}

        result = depth do
          res = case options[:position]
          when :subject, :object
            # attempt base_uri replacement
            iri.to_s.sub(base.to_s, "")
          when :predicate
            # attempt vocab replacement
            iri == RDF.type ? '@type' : iri.to_s.sub(vocab.to_s, "")
          else # :datatype
            iri.to_s
          end
        
          # If the above didn't result in a compacted representation, try a CURIE
          res == iri.to_s ? (get_curie(iri) || iri.to_s) : res
        end

        debug {"=> #{result.inspect}"}
        result
      end
    end

    ##
    # Expand a value
    #
    # @param [String] key
    #   Associated key used to find coercion rules
    # @param [Hash, String] value
    #   Value (literal or IRI) to be expanded
    # @param  [Hash{Symbol => Object}] options
    #
    # @return [Hash] Object representation of value
    # @raise [RDF::ReaderError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-expansion
    def expand_value(key, value, options = {})
      predicate = expand_iri(key, :position => :predicate)

      depth(options) do
        debug("expand_value") {"predicate: #{predicate}, value: #{value.inspect}"}
        result = case value
        when Hash
          res = Hash.new
          value.each_pair do |k, v|
            res[k] = expand_value(k, v)
          end
          res
        when Array
          # Expand individual elements
          members = value.map {|v| expand_value(key, v, options)}

          # Use expanded list form if lists are coerced
          list[predicate] ? {'@list' => members} : members
        when TrueClass, FalseClass, Integer, BigDecimal, Double
          value
        when RDF::URI
          {'@id' => value.to_s}
        when RDF::Literal::Integer, RDF::Literal::Double
          value.object
        when RDF::Literal
          res = Hash.new
          res['@literal'] = value.to_s
          res['@type'] = value.datatype.to_s if value.has_datatype?
          res['@language'] = value.language.to_s if value.has_language?
          res
        else
          case coerce[predicate]
          when '@id'
            {'@id' => expand_iri(value, :position => :object)}
          when String, RDF::URI
            res = Hash.new
            res['@literal'] = value.to_s
            res['@language'] = language if language
          else
            value.to_s
          end
        end
        
        debug {"=> #{result.inspect}"}
        result
      end
    end

    ##
    # Compact a value
    #
    # @param [String] key
    #   Associated key used to find coercion rules
    # @param [Hash] value
    #   Value (literal or IRI), in full object representation, to be compacted
    # @param  [Hash{Symbol => Object}] options
    #
    # @return [Hash] Object representation of value
    # @raise [ProcessingError] if the iri cannot be expanded
    # @see http://json-ld.org/spec/latest/json-ld-api/#value-compaction
    def compact_value(key, value, options = {})
      predicate = expand_iri(key, :position => :predicate).to_s
      raise ProcessingError, "attempt to compact a non-object value" unless value.is_a?(Hash)

      depth(options) do
        debug("compact_value") {"predicate: #{predicate.inspect}, value: #{value.inspect}\n"}
        result = case
        when list[predicate] && value['@list']
          # Compact an expanded list representation
          debug {" (list)"}
          value['@list']
        when list[predicate] == '@id'
          # Compact an @id coercion
          debug {" (@id)"}
          value = value['@id']
        when value['@language'] && value['@language'] == language
          # Compact language
          debug {" (@language) == #{language}"}
          value = value['@literal']
        when value['@type'] && expand_iri(value['@type'], :position => :datatype) == coerce[predicate]
          # Compact common datatype
          debug {" (@type) == #{coerce[predicate]}"}
          value = value['@literal']
        when !value['@language'] && !value['@type'] && !coerce[predicate] && !language
          # Compact simple literal to string
          debug {" (!@language && !@type && !coerce && !language)"}
          value = value['@literal']
        when value['@type']
          # Compact datatype
          debug {" (@type)"}
          value['@type'] = compact_iri(value['@type'], :position => :datatype)
          value
        else
          # Otherwise, use original value
          value
        end
        
        debug {"=> #{result.inspect}"}
        result
      end
    end

    def inspect
      v = %w([EvaluationContext) + %w(base vocab).map {|a| "#{a}=#{self.send(a).inspect}"}
      v << "mappings[#{mappings.keys.length}]=#{mappings}"
      v << "coerce[#{coerce.keys.length}]=#{coerce}"
      v << "list[#{list.length}]=#{list}"
      v.join(", ") + "]"
    end
    
    def dup
      # Also duplicate mappings, coerce and list
      ec = super
      ec.mappings = mappings.dup
      ec.coerce = coerce.dup
      ec.list = list.dup
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
      @@bnode_cache[value.to_s] ||= RDF::Node.new
    end

    ##
    # Return a CURIE for the IRI, or nil. Adds namespace of CURIE to defined prefixes
    # @param [RDF::Resource] resource
    # @return [String, nil] value to use to identify IRI
    def get_curie(resource)
      debug {"get_curie(#{resource.inspect})"}
      case resource
      when RDF::Node
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
        add_mapping(prefix, u)
        iri.sub(u.to_s, "#{prefix}:").sub(/:$/, '')
      when @options[:standard_prefixes] && vocab = RDF::Vocabulary.detect {|v| iri.index(v.to_uri.to_s) == 0}
        prefix = vocab.__name__.to_s.split('::').last.downcase
        add_mapping(prefix, vocab.to_uri.to_s)
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