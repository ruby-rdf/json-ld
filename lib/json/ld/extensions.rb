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
