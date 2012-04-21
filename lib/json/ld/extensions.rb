module RDF
  class Graph
    # Resource properties
    #
    # Properties arranged as a hash with the predicate Term as index to an array of resources or literals
    #
    # Example:
    #   graph.load(':foo a :bar; rdfs:label "An example" .', "http://example.com/")
    #   graph.resources(URI.new("http://example.com/subject")) =>
    #   {
    #     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" => [<http://example.com/#bar>],
    #     "http://example.com/#label"                       => ["An example"]
    #   }
    def properties(subject, recalc = false)
      @properties ||= {}
      @properties.delete(subject.to_s) if recalc
      @properties[subject.to_s] ||= begin
        hash = Hash.new
        self.query(:subject => subject) do |statement|
          pred = statement.predicate.to_s

          hash[pred] ||= []
          hash[pred] << statement.object
        end
        hash
      end
    end

    # Get type(s) of subject, returns a list of symbols
    def type_of(subject)
      query(:subject => subject, :predicate => RDF.type).map {|st| st.object}
    end
  end
  
  class URI
    def to_s
      @uri.to_s
    end
  end
  
  class Literal
    class Double
      ##
      # Converts this literal into its canonical lexical representation.
      # Update to use %.15E to avoid precision problems
      def canonicalize!
        @string = case
          when @object.nan?      then 'NaN'
          when @object.infinite? then @object.to_s[0...-'inity'.length].upcase
          when @object.zero?     then '0.0E0'
          else
            i, f, e = ('%.15E' % @object.to_f).split(/[\.E]/)
            f.sub!(/0*$/, '')           # remove any trailing zeroes
            f = '0' if f.empty?         # ...but there must be a digit to the right of the decimal point
            e.sub!(/^\+?0+(\d)$/, '\1') # remove the optional leading '+' sign and any extra leading zeroes
            "#{i}.#{f}E#{e}"
        end
        @object = Float(@string) unless @object.nil?
        self
      end
    end
  end
end

if RUBY_VERSION < "1.9"
  class InsertOrderPreservingHash < Hash
    include Enumerable

    def initialize(*args, &block)
      super
      @ordered_keys = []
    end

    def []=(key, val)
      @ordered_keys << key unless has_key? key
      super
    end

    def each
      @ordered_keys.each {|k| yield(k, self[k])}
    end
    alias :each_pair :each

    def each_value
      @ordered_keys.each {|k| yield(super[k])}
    end

    def each_key
      @ordered_keys.each {|k| yield k}
    end

    def keys
      @ordered_keys
    end

    def clear
      @ordered_keys.clear
      super
    end

    def delete(k, &block)
      @ordered_keys.delete(k)
      super
    end

    def reject!
      del = []
      each_pair {|k,v| del << k if yield k,v}
      del.each {|k| delete k}
      del.empty? ? nil : self
    end

    def delete_if(&block)
      reject!(&block)
      self
    end

    def merge!(other)
      new_keys = other.instance_variable_get(:@ordered_keys) || other.keys
      new_keys -= @ordered_keys
      @ordered_keys += new_keys
      super
      self
    end
    
    def merge(other)
      self.dup.merge!(other)
    end
  end
  
  class Hash
    def self.ordered(obj = nil, &block)
      InsertOrderPreservingHash.new(obj, &block)
    end
  end
else
  class Hash
    def self.ordered(obj = nil, &block)
      Hash.new(obj, &block)
    end
  end
end