# coding: utf-8
$:.unshift "."
require File.join(File.dirname(__FILE__), 'spec_helper')

describe JSON::LD::Reader do
  describe "test suite" do
    require 'suite_helper'
    
    %w(required optional buggy).each do |classification|
      describe "that are #{classification}" do
        Fixtures::TestCase.for_specific(Fixtures::TestCase::Test.send(classification)) do |t|
          specify "test #{t.name}: #{t.title}#{",  (negative test)" if t.expectedResults.false?}" do
            begin
              t.debug = []
              reader = RDF::Reader.open(t.inputDocument,
                :base_uri => t.inputDocument,
                :debug => t.debug,
                :format => :jsonld)
              reader.should be_a JSON::LD::Reader

              graph = RDF::Graph.new << reader
              query = Kernel.open(t.resultDocument)
              graph.should pass_query(query, t)
            rescue RSpec::Expectations::ExpectationNotMetError => e
              if classification != "required"
                pending("#{classification} test") {  raise }
              else
                raise
              end
            end
          end
        end
      end
    end
  end

  def parse(input, options = {})
    @debug = []
    graph = options[:graph] || RDF::Graph.new
    graph << JSON::LD::Reader.new(input, {:debug => @debug, :validate => true, :canonicalize => false}.merge(options))
  end
end