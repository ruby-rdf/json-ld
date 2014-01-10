module RDF
  class Graph
    # Resource properties
    #
    # Properties arranged as a hash with the predicate Term as index to an array of resources or literals
    #
    # Example:
    #     graph.load(':foo a :bar; rdfs:label "An example" .', "http://example.com/")
    #     graph.resources(URI.new("http://example.com/subject")) =>
    #     {
    #       "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" => \[<http://example.com/#bar>\],
    #       "http://example.com/#label"                       => \["An example"\]
    #     }
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
  
  class Node
    # Odd case of appending to a BNode identifier
    def +(value)
      Node.new(id + value.to_s)
    end
  end
end

class Array
  # Sort values, but impose special keyword ordering
  # @yield a, b
  # @yieldparam [Object] a
  # @yieldparam [Object] b
  # @yieldreturn [Integer]
  # @return [Array]
  KW_ORDER = %w(@base @id @value @type @language @vocab @container @graph @list @set @index).freeze

  # Order, considering keywords to come before other strings
  def kw_sort
    self.sort do |a, b|
      a = "@#{KW_ORDER.index(a)}" if KW_ORDER.include?(a)
      b = "@#{KW_ORDER.index(b)}" if KW_ORDER.include?(b)
      a <=> b
    end
  end

  # Order terms, length first, then lexographically
  def term_sort
    self.sort do |a, b|
      len_diff = a.length <=> b.length
      len_diff == 0 ? a <=> b : len_diff
    end
  end
end
