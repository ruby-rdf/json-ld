module JSON::LD
  module Utils
    ##
    # Is value a subject? A value is a subject if
    # * it is a Hash
    # * it is not a @value, @set or @list
    # * it has more than 1 key or any key is not @id
    # @param [Object] value
    # @return [Boolean]
    def subject?(value)
      value.is_a?(Hash) &&
        (value.keys & %w(@value @list @set)).empty? &&
        !(value.keys - ['@id']).empty?
    end

    ##
    # Is value a subject reference?
    # @param [Object] value
    # @return [Boolean]
    def subject_reference?(value)
      value.is_a?(Hash) && value.keys == %w(@id)
    end

    ##
    # Is value a blank node? Value is a blank node
    #
    # @param [Object] value
    # @return [Boolean]
    def blank_node?(value)
      value.is_a?(Hash) && value.fetch('@id', '_:')[0,2] == '_:'
    end

    private

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

  ##
  # Utility class for mapping old blank node identifiers, or unnamed blank nodes to new identifiers
  class BlankNodeNamer < Hash
    # @prefix [String] prefix
    def initialize(prefix)
      @prefix = "_:#{prefix}0"
      super
    end
    
    ##
    # Get a new mapped name for `old`
    #
    # @param [String] old
    # @return [String]
    def get_name(old)
      if old && self.has_key?(old)
        self[old]
      elsif old
        self[old] = @prefix.dup
        @prefix.succ!
        self[old]
      else
        # Not referenced, just return a new unique value
        cur = @prefix.dup
        @prefix.succ!
        cur
      end
    end
  end
end