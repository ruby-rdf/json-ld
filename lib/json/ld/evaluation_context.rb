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

    # A list of current, in-scope URI mappings.
    #
    # @attr [Hash{String => String}]
    attr :mappings, true

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
    def initialize(options)
      @base = nil
      @mappings =  {}
      @vocab = nil
      @coerce = {}
      @list = []
      @options = options
      yield(self) if block_given?
    end

    # Create an Evaluation Context by parsing the input.
    #
    # @param [IO, Array, Hash, String] input
    # @return [EvaluationContext] context
    # @raise [IOError]
    #   on a remote context load error, syntax error, or a reference to a term which is not defined.
    # @yield debug
    # @yieldparam [Proc] block to call for debug output
    def self.parse(context)
      EvaluationContext.new.parse(context)
    end

    # Create an Evaluation Context using an existing context as a start by parsing the input.
    #
    # @param [IO, Array, Hash, String] input
    # @return [EvaluationContext] context
    # @raise [IOError]
    #   on a remote context load error, syntax error, or a reference to a term which is not defined.
    # @yield debug
    # @yieldparam [Proc] block to call for debug output
    def parse(context)
      case context
      when IO, StringIO
        yield lambda {"io: #{context}"} if block_given?
        # Load context document, if it is a string
        ctx = JSON.load(context)
        if ctx.is_a?(Hash) && ctx["@context"]
          parse(ctx["@context"])
        else
          yield lambda {"Failed to retrieve @context from remote document at #{context}: #{e.message}"}
          raise RDF::ReaderError, "Failed to retrieve @context from remote document at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when String
        yield lambda {"remote: #{context}"} if block_given?
        # Load context document, if it is a string
        ctx = nil
        begin
          open(context.to_s) {|f| ctx = parse(f)}
        rescue JSON::ParserError => e
          yield lambda {"Failed to retrieve @context from remote document at #{context}: #{e.message}"}
          raise RDF::ReaderError, "Failed to parse remote context at #{context}: #{e.message}" if @options[:validate]
          self.dup
        end
      when Array
        # Process each member of the array in order, updating the active context
        # Updates evaluation context serially during parsing
        yield lambda {"Array"} if block_given?
        ec = self
        context.each {|c| ec = ec.parse(c)}
        ec
      when Hash
        new_ec = self.dup
        context.each do |key, value|
          # Expand a string value, unless it matches a keyword
          value = expand_base(value) if value.is_a?(String) && value[0,1] != '@'
          yield lambda {"Hash[#{key}] = #{value.inspect}"} if block_given?
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
              if key.match(NC_REGEXP) || key.empty?
                # It defines a term, look up @iri, or do vocab expansion
                # Given @iri, expand it, otherwise resolve key relative to @vocab
                new_ec.mappings[key] = if value["@iri"]
                  expand_base(value["@iri"])
                else
                  # Expand term using vocab
                  expand_vocab(key)
                end
              
                prop = new_ec.mappings[key].to_s

                yield lambda {"Term definition #{key} => #{prop.inspect}"} if block_given?
              else
                # It is not a term definition, and must be a prefix:suffix or IRI
                prop = expand_vocab(key).to_s
                yield lambda {"No term definition #{key} => #{prop.inspect}"} if block_given?
              end

              # List inclusion
              if value["@list"]
                new_ec.list << prop unless new_ec.list.include?(prop)
              end

              # Coercion
              case value["@coerce"]
              when Array
                # With an array, there can be two items, one of which must be @list
                if value["@coerce"].include?(@list)
                  dtl = value["@coerce"] - "@list"
                  raise RDF::ReaderError,
                    "Coerce array for #{key} must only contain @list and a datatype: #{value['@coerce'].inspect}" unless
                    dtl.length == 1
                  case dtl.first
                  when "@iri"
                    yield lambda {"@coerce @iri"} if block_given?
                    new_ec.coerce[prop] = '@iri'
                  when String
                    dt = expand_vocab(dtl.first)
                    yield lambda {"@coerce #{dt}"} if block_given?
                    new_ec.coerce[prop] = dt
                  end
                elsif @options[:validate]
                  raise RDF::ReaderError, "Coerce array for #{key} must contain @list: #{value['@coerce'].inspect}"
                end
                new_ec.list << prop unless new_ec.list.include?(prop)
              when Hash
                # Must be of the form {"@list" => dt}
                case value["@coerce"]["@list"]
                when "@iri"
                  yield lambda {"@coerce @iri"} if block_given?
                  new_ec.coerce[prop] = '@iri'
                when String
                  dt = expand_vocab(value["@coerce"]["@list"])
                  yield lambda {"@coerce #{dt}"} if block_given?
                  new_ec.coerce[prop] = dt
                when nil
                  raise RDF::ReaderError, "Unknown coerce hash for #{key}: #{value['@coerce'].inspect}" if @options[:validate]
                end
                new_ec.list << prop unless new_ec.list.include?(prop)
              when "@iri"
                yield lambda {"@coerce @iri"} if block_given?
                new_ec.coerce[prop] = '@iri'
              when "@list"
                dt = expand_vocab(value["@coerce"])
                yield lambda {"@coerce @list"} if block_given?
                new_ec.list << prop unless new_ec.list.include?(prop)
              when String
                dt = expand_vocab(value["@coerce"])
                yield lambda {"@coerce #{dt}"} if block_given?
                new_ec.coerce[prop] = dt
              end
            else
              # Given a string (or URI), us it
              new_ec.mappings[key] = value
            end
          end
        end
      
        if context['@coerce']
          # This is deprecated code
          raise RDF::ReaderError, "Expected @coerce to reference an associative array" unless context['@coerce'].is_a?(Hash)
          context['@coerce'].each do |type, property|
            yield lambda {"type=#{type}, prop=#{property}"} if block_given?
            type_uri = new_ec.expand_vocab(type).to_s
            [property].flatten.compact.each do |prop|
              p = new_ec.expand_vocab(prop).to_s
              if type == '@list'
                # List is managed separate from types, as it is maintained in normal form.
                new_ec.list << p unless new_ec.list.include?(p)
              else
                new_ec.coerce[p] = type_uri
              end
            end
          end
        end

        new_ec
      end
    end


    ##
    # Expand a term
    #
    # @param [String] term
    # @param [String] base Base to apply to URIs
    #
    # @return [RDF::URI]
    # @raise [RDF::ReaderError] if the term cannot be expanded
    # @see http://json-ld.org/spec/ED/20110507/#markup-of-rdf-concepts
    def expand_term(term, base)
      return term unless term.is_a?(String)
      prefix, suffix = term.split(":", 2)
      if prefix == '_'
        bnode(suffix)
      elsif self.mappings.has_key?(prefix)
        uri(self.mappings[prefix] + suffix.to_s)
      elsif base
        base.respond_to?(:join) ? base.join(term) : uri(base + term)
      elsif term.to_s[0,1] == "@"
        term
      else
        uri(term)
      end
    end

    ##
    # Expand a term relative to the current base
    # @param [String] term
    #
    # @return [RDF::URI]
    # @raise [RDF::ReaderError] if the term cannot be expanded
    # @see http://json-ld.org/spec/ED/20110507/#markup-of-rdf-concepts
    def expand_base(term)
      expand_term(term, self.base)
    end
    
    ##
    # Expand a term relative to the current vocabulary
    # @param [String] term
    #
    # @return [RDF::URI]
    # @raise [RDF::ReaderError] if the term cannot be expanded
    # @see http://json-ld.org/spec/ED/20110507/#markup-of-rdf-concepts
    def expand_vocab(term)
      expand_term(term, self.vocab)
    end
    
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

    def inspect
      v = %w([EvaluationContext) + %w(base vocab).map {|a| "#{a}='#{self.send(a).inspect}'"}
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
      ec
    end
  end
end