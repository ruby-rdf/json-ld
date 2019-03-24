# -*- encoding: utf-8 -*-
# frozen_string_literal: true
module RDF
  class Node
    # Odd case of appending to a BNode identifier
    def +(value)
      Node.new(id + value.to_s)
    end
  end

  class Statement
    # Validate extended RDF
    def valid_extended?
      has_subject?    && subject.resource? && subject.valid_extended? &&
      has_predicate?  && predicate.resource? && predicate.valid_extended? &&
      has_object?     && object.term? && object.valid_extended? &&
      (has_graph?      ? (graph_name.resource? && graph_name.valid_extended?) : true)
    end
  end

  class URI 
    # Validate extended RDF
    def valid_extended?
      self.valid?
    end
  end

  class Node 
    # Validate extended RDF
    def valid_extended?
      self.valid?
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

  module Util
    module File
      # Add contextUrl accessor
      class RemoteDocument
        # @return [String]
        #   The URL of a remote context as specified by an HTTP Link header with rel=`http://www.w3.org/ns/json-ld#context`
        attr_accessor :contextUrl

        # @return [String, Array<Hash>, Hash]
        #   The retrieved document, either as raw text or parsed JSON
        def document
          @document ||= self.read
        end
      end
    end
  end
end

class Object
  # Default canonicalization output for Ruby objects
  # @return [String]
  def to_json_c14nx
    self.to_json
  end
end

class Hash
  # Output JSON with keys sorted lexicographically
  # @return [String]
  def to_json_c14nx
    "{" + self.
      keys.
      sort.
      map {|k| k.to_json_c14nx + ':' + self[k].to_json_c14nx}
      .join(',') +
    '}'
  end
end

class Array
  def to_json_c14nx
    '[' + self.map(&:to_json_c14nx).join(',') + ']'
  end

  # Optionally order items
  #
  # @param [Boolean] ordered
  # @return [Array]
  def opt_sort(ordered: false)
    ordered ? self.sort : self
  end
end

class Numeric
  def to_json_c14nx
    RDF::Literal.new(self.ceil != self ? self : self.numerator, canonicalize: true).to_s
  end
end
