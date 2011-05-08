$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$:.unshift File.dirname(__FILE__)

require 'rubygems'
require 'rspec'
require 'matchers'
require 'bigdecimal'  # XXX Remove Me
require 'json/ld'
require 'rdf/ntriples'
require 'rdf/spec'
require 'rdf/spec/matchers'
require 'rdf/isomorphic'

include Matchers

module RDF
  module Isomorphic
    alias_method :==, :isomorphic_with?
  end
  class Graph
    def to_ntriples
      RDF::Writer.for(:ntriples).buffer do |writer|
        self.each_statement do |statement|
          writer << statement
        end
      end
    end
    def dump
      b = []
      self.each_statement do |statement|
        b << statement.to_triple.inspect
      end
      b.join("\n")
    end
  end
end

::RSpec.configure do |c|
  c.filter_run :focus => true
  c.run_all_when_everything_filtered = true
  c.exclusion_filter = {
    :ruby => lambda { |version| !(RUBY_VERSION.to_s =~ /^#{version.to_s}/) },
  }
  c.include(Matchers)
  c.include(RDF::Spec::Matchers)
end

# Serialize graph and replace bnodes with predictable versions, return as sorted array  
def normalize_bnodes(graph, anon = "a")
  anon_ctx = {}
  # Find and replace all BNodes within graph string
  g_str = graph.to_ntriples
  anon_entries = g_str.scan(/_:g\d+/).sort.uniq
  anon_entries.each do |a|
    anon_ctx[a] = "_:#{anon}"
    anon = anon.succ
  end
  
  g_str.gsub(/_:g\d+/) { |bn| anon_ctx[bn] }.split("\n").sort
end
