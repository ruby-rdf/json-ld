# -*- encoding: utf-8 -*-
# frozen_string_literal: true
module RDF
  class Node
    # Odd case of appending to a BNode identifier
    def +(value)
      Node.new(id + value.to_s)
    end
  end
end

class Array
  # Order terms, length first, then lexographically
  def term_sort
    self.sort do |a, b|
      len_diff = a.length <=> b.length
      len_diff == 0 ? a <=> b : len_diff
    end
  end
end
