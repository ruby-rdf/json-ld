module JSON::LD
  module Utils
    ##
    # Is value a node? A value is a node if
    # * it is a Hash
    # * it is not a @value, @set or @list
    # * it has more than 1 key or any key is not @id
    # @param [Object] value
    # @return [Boolean]
    def node?(value)
      value.is_a?(Hash) &&
        (value.keys & %w(@value @list @set)).empty? &&
        !(value.keys - ['@id']).empty?
    end

    ##
    # Is value a node reference?
    # @param [Object] value
    # @return [Boolean]
    def node_reference?(value)
      value.is_a?(Hash) && value.keys == %w(@id)
    end

    ##
    # Is value a blank node? Value is a blank node
    #
    # @param [Object] value
    # @return [Boolean]
    def blank_node?(value)
      case value
      when nil    then true
      when String then value[0,2] == '_:'
      else
        (node?(value) || node_reference?(value)) && value.fetch('@id', '_:')[0,2] == '_:'
      end
    end

    ##
    # Is value an expaned @list?
    #
    # @param [Object] value
    # @return [Boolean]
    def list?(value)
      value.is_a?(Hash) && value.has_key?('@list')
    end

    ##
    # Is value annotated?
    #
    # @param [Object] value
    # @return [Boolean]
    def index?(value)
      value.is_a?(Hash) && value.has_key?('@index')
    end

    ##
    # Is value literal?
    #
    # @param [Object] value
    # @return [Boolean]
    def value?(value)
      value.is_a?(Hash) && value.has_key?('@value')
    end

    ##
    # Represent an id as an IRI or Blank Node
    # @param [String] id
    # @param [RDF::URI] base (nil)
    # @return [RDF::Resource]
    def as_resource(id, base = nil)
      @nodes ||= {} # Re-use BNodes
      if id[0,2] == '_:'
        (@nodes[id] ||= RDF::Node.new(id[2..-1]))
      elsif base
        base.join(id)
      else
        RDF::URI(id)
      end
    end

    private

    # Merge the last value into an array based for the specified key if hash is not null and value is not already in that array
    def merge_value(hash, key, value)
      return unless hash
      values = hash[key] ||= []
      if key == '@list'
        values << value
      elsif list?(value)
        values << value
      elsif !values.include?(value)
        values << value
      end
    end

    # Merge values into compacted results, creating arrays if necessary
    def merge_compacted_value(hash, key, value)
      return unless hash
      case hash[key]
      when nil then hash[key] = value
      when Array
        if value.is_a?(Array)
          hash[key].concat(value)
        else
          hash[key] << value
        end
      else
        hash[key] = [hash[key]]
        if value.is_a?(Array)
          hash[key].concat(value)
        else
          hash[key] << value
        end
      end
    end

    # Add debug event to debug array, if specified
    #
    #   param [String] message
    #   yieldreturn [String] appended to message, to allow for lazy-evaulation of message
    def debug(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      return unless ::JSON::LD.debug? || @options[:debug]
      depth = options[:depth] || @depth || 0
      list = args
      list << yield if block_given?
      message = " " * depth * 2 + (list.empty? ? "" : list.join(": "))
      puts message if JSON::LD::debug?
      @options[:debug] << message if @options[:debug].is_a?(Array)
    end

    # Increase depth around a method invocation
    def depth(options = {})
      old_depth = @depth || 0
      @depth = (options[:depth] || old_depth) + 1
      yield
    ensure
      @depth = old_depth
    end
  end

  ##
  # Utility class for mapping old blank node identifiers, or unnamed blank
  # nodes to new identifiers
  class BlankNodeMapper < Hash
    ##
    # Just return a Blank Node based on `old`. Manufactures
    # a node if `old` is nil or empty
    # @param [String] old ("")
    # @return [String]
    def get_sym(old = "")
      old = RDF::Node.new.to_s if old.to_s.empty?
      old.to_s.sub(/_:/, '')
    end

    ##
    # Get a new mapped name for `old`
    #
    # @param [String] old ("")
    # @return [String]
    def get_name(old = "")
      "_:" + get_sym(old)
    end
  end

  class BlankNodeUniqer < BlankNodeMapper
    ##
    # Use the uniquely generated bnodes, rather than a sequence
    # @param [String] old ("")
    # @return [String]
    def get_sym(old = "")
      old = old.to_s.sub(/_:/, '')
      if old && self.has_key?(old)
        self[old]
      elsif !old.empty?
        self[old] = RDF::Node.new.to_unique_base[2..-1]
      else
        RDF::Node.new.to_unique_base[2..-1]
      end
    end
  end

  class BlankNodeNamer < BlankNodeMapper
    # @param [String] prefix
    def initialize(prefix)
      @prefix = prefix.to_s
      @num = 0
      super
    end

    ##
    # Get a new symbol mapped from `old`
    # @param [String] old ("")
    # @return [String]
    def get_sym(old = "")
      old = old.to_s.sub(/_:/, '')
      if old && self.has_key?(old)
        self[old]
      elsif !old.empty?
        @num += 1
        #puts "allocate #{@prefix + (@num - 1).to_s} to #{old.inspect}"
        self[old] = @prefix + (@num - 1).to_s
      else
        # Not referenced, just return a new unique value
        @num += 1
        #puts "allocate #{@prefix + (@num - 1).to_s} to #{old.inspect}"
        @prefix + (@num - 1).to_s
      end
    end
  end
end