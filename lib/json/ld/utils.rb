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
      (node?(value) || node_reference?(value)) && value.fetch('@id', '_:')[0,2] == '_:'
    end

    ##
    # Is value an expaned @list?
    #
    # @param [Object] value
    # @return [Boolean]
    def list?(value)
      value.is_a?(Hash) && value.keys == %w(@list)
    end

    ##
    # Is value literal?
    #
    # @param [Object] value
    # @return [Boolean]
    def value?(value)
      value.is_a?(Hash) && value.has_key?('@value')
    end

    private

    # Add debug event to debug array, if specified
    #
    #   param [String] message
    #   yieldreturn [String] appended to message, to allow for lazy-evaulation of message
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

  ##
  # Utility class for mapping old blank node identifiers, or unnamed blank
  # nodes to new identifiers
  class BlankNodeMapper < Hash
    ##
    # Just return a Blank Node based on `old`
    # @param [String] old
    # @return [String]
    def get_sym(old)
      old.to_s.sub(/_:/, '')
    end

    ##
    # Get a new mapped name for `old`
    #
    # @param [String] old
    # @return [String]
    def get_name(old)
      "_:" + get_sym(old)
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
    # @param [String] old
    # @return [String]
    def get_sym(old)
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