require 'open-uri'
require 'json'

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
    # The @coerce keyword is used to specify type coersion rules for the data. For each key in the map, the
    # key is a String representation of the property for which String values will be coerced and
    # the value is the datatype (or @iri) to coerce to. Type coersion for
    # the value `@iri` asserts that all vocabulary terms listed should undergo coercion to an IRI,
    # including `@base` processing for relative IRIs and CURIE processing for compact IRI Expressions like
    # `foaf:homepage`.
    #
    # @attr [Hash{String => String}]
    attr :coerce, true

    # List coercion
    #
    # The @list keyword is used to specify that properties having an array value are to be treated
    # as an ordered list, rather than a normal unordered list
    # @attr [Array<String>]
    attr :list, true
    
    # Default language
    #
    # This adds a language to plain strings that aren't otherwise coerced
    # @attr [Symbol]
    attr :language, true
    
    # Global options used in generating IRIs
    # @attr [Hash] options
    attr :options, true

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
      @list = []
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
        ctx = JSON.load(context)
        if ctx.is_a?(Hash) && ctx["@context"]
          parse(ctx["@context"])
        else
          debug("parse") {"Failed to retrieve @context from remote document at #{context}: #{e.message}"}
          raise RDF::ReaderError, "Failed to retrieve @context from remote document at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when String
        debug("parse") {"remote: #{context}"}
        # Load context document, if it is a string
        ctx = nil
        begin
          open(context.to_s) {|f| ctx = parse(f)}
        rescue JSON::ParserError => e
          debug("parse") {"Failed to retrieve @context from remote document at #{context}: #{e.message}"}
          raise RDF::ReaderError, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when Array
        # Process each member of the array in order, updating the active context
        # Updates evaluation context serially during parsing
        debug("parse") {"Array"}
        ec = self
        context.each {|c| ec = ec.parse(c)}
        ec
      when Hash
        new_ec = self.dup
        context.each do |key, value|
          # Expand a string value, unless it matches a keyword
          value = expand_iri(value, :position => :predicate) if value.is_a?(String) && value[0,1] != '@'
          debug("parse") {"Hash[#{key}] = #{value.inspect}"}
          case key
          when '@vocab'    then new_ec.vocab = value.to_s
          when '@base'     then new_ec.base  = uri(value)
          when '@language' then new_ec.language = value.to_s.to_sym
          when '@coerce'
            # Process after prefix mapping.
            # FIXME: deprectaed
          else
            # If value is a Hash process contents
            case value
            when Hash
              if term_valid?(key)
                # It defines a term, look up @iri, or do vocab expansion
                # Given @iri, expand it, otherwise resolve key relative to @vocab
                new_ec.add_mapping(key, expand_iri(value["@iri"] || key, :position => :predicate))
              
                prop = new_ec.mappings[key].to_s

                debug("parse") {"Term definition #{key} => #{prop.inspect}"}
              else
                # It is not a term definition, and must be a prefix:suffix or IRI
                prop = expand_iri(key, :position => :predicate).to_s
                debug("parse") {"No term definition #{key} => #{prop.inspect}"}
              end

              # List inclusion
              if value["@list"]
                new_ec.list << prop unless new_ec.list.include?(prop)
              end

              # Coercion
              value["@coerce"] = value["@datatype"] if value.has_key?("@datatype") && !value.has_key?("@coerce")
              case value["@coerce"]
              when Array
                # Form is { "term" => { "@coerce" => ["@list", "xsd:string"]}}
                # With an array, there can be two items, one of which must be @list
                # FIXME: this alternative unlikely
                if value["@coerce"].include?(@list)
                  dtl = value["@coerce"] - "@list"
                  raise RDF::ReaderError,
                    "Coerce array for #{key} must only contain @list and a datatype: #{value['@coerce'].inspect}" unless
                    dtl.length == 1
                  case dtl.first
                  when "@iri"
                    debug("parse") {"@coerce @iri"}
                    new_ec.coerce[prop] = '@iri'
                  when String
                    dt = expand_iri(dtl.first, :position => :datatype)
                    debug("parse") {"@coerce #{dt}"}
                    new_ec.coerce[prop] = dt
                  end
                elsif @options[:validate]
                  raise RDF::ReaderError, "Coerce array for #{key} must contain @list: #{value['@coerce'].inspect}"
                end
                new_ec.list << prop unless new_ec.list.include?(prop)
              when Hash
                # Must be of the form { "term" => { "@coerce" => {"@list" => "xsd:string"}}}
                case value["@coerce"]["@list"]
                when "@iri"
                  debug("parse") {"@coerce @iri"}
                  new_ec.coerce[prop] = '@iri'
                when String
                  dt = expand_iri(value["@coerce"]["@list"], :position => :datatype)
                  debug("parse") {"@coerce #{dt}"}
                  new_ec.coerce[prop] = dt
                when nil
                  raise RDF::ReaderError, "Unknown coerce hash for #{key}: #{value['@coerce'].inspect}" if @options[:validate]
                end
                new_ec.list << prop unless new_ec.list.include?(prop)
              when "@iri"
                # Must be of the form { "term" => { "@coerce" => "@iri"}}
                debug("parse") {"@coerce @iri"}
                new_ec.coerce[prop] = '@iri'
              when "@list"
                # Must be of the form { "term" => { "@coerce" => "@list"}}
                dt = expand_iri(value["@coerce"], :position => :predicate)
                debug("parse") {"@coerce @list"}
                new_ec.list << prop unless new_ec.list.include?(prop)
              when String
                # Must be of the form { "term" => { "@coerce" => "xsd:string"}}
                dt = expand_iri(value["@coerce"], :position => :predicate)
                debug("parse") {"@coerce #{dt}"}
                new_ec.coerce[prop] = dt
              end
            else
              # Given a string (or URI), us it
              new_ec.add_mapping(key, value)
            end
          end
        end
      
        if context['@coerce']
          # This is deprecated code
          raise RDF::ReaderError, "Expected @coerce to reference an associative array" unless context['@coerce'].is_a?(Hash)
          context['@coerce'].each do |type, property|
            debug("parse") {"type=#{type}, prop=#{property}"}
            type_uri = new_ec.expand_iri(type, :position => :predicate).to_s
            [property].flatten.compact.each do |prop|
              p = new_ec.expand_iri(prop, :position => :predicate).to_s
              if type == '@list'
                # List is managed separate from types, as it is maintained in normal form.
                new_ec.list << p unless new_ec.list.include?(p)
              else
                new_ec.coerce[p] = type_uri
              end
            end
          end
        end

        debug("parse") {"iri_to_term: #{new_ec.iri_to_term.inspect}"}

        new_ec
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
    # @param [String] base Base to apply to URIs
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