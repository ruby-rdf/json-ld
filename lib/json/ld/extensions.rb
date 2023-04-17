# frozen_string_literal: true

module RDF
  class Node
    # Odd case of appending to a BNode identifier
    def +(other)
      Node.new(id + other.to_s)
    end
  end

  class Statement
    # Validate extended RDF
    def valid_extended?
      subject? && subject.resource? && subject.valid_extended? &&
        predicate?  && predicate.resource? && predicate.valid_extended? &&
        object?     && object.term? && object.valid_extended? &&
        (graph? ? (graph_name.resource? && graph_name.valid_extended?) : true)
    end
  end

  class URI
    # Validate extended RDF
    def valid_extended?
      valid?
    end
  end

  class Node
    # Validate extended RDF
    def valid_extended?
      valid?
    end
  end

  class Literal
    # Validate extended RDF
    def valid_extended?
      return false if language? && language.to_s !~ /^[a-zA-Z]+(-[a-zA-Z0-9]+)*$/
      return false if datatype? && datatype.invalid?

      value.is_a?(String)
    end
  end
end

class Array
  # Optionally order items
  #
  # @param [Boolean] ordered
  # @return [Array]
  def opt_sort(ordered: false)
    ordered ? sort : self
  end
end
