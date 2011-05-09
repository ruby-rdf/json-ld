$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$:.unshift File.dirname(__FILE__)

require 'rubygems'
require 'rspec'
require 'matchers'
require 'bigdecimal'  # XXX Remove Me
require 'json/ld'
require 'rdf/ntriples'
require 'rdf/n3'
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

# Heuristically detect the input stream
def detect_format(stream)
  # Got to look into the file to see
  if stream.is_a?(IO) || stream.is_a?(StringIO)
    stream.rewind
    string = stream.read(1000)
    stream.rewind
  else
    string = stream.to_s
  end
  case string
  when /@prefix/i then :n3
  else                 :ntriples
  end
end
