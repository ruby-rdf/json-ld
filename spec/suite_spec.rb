# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::Reader do
  describe "test suite" do
    require 'suite_helper'
    
    Fixtures::JSONLDTest::Manifest.each do |m|
      describe m.name do
        m.entries.each do |m2|
          describe m2.name do
            m2.entries.each do |t|
              case t
              when Fixtures::JSONLDTest::RDFTest
                specify "RDF Test - #{File.basename(t.inputDocument.to_s)}: #{t.name}" do
                  t.debug = []
                  reader = RDF::Reader.open(t.inputDocument,
                    :base_uri => t.inputDocument,
                    :debug => t.debug,
                    :format => :jsonld)
                  reader.should be_a JSON::LD::Reader

                  graph = RDF::Graph.new << reader
                  graph.should pass_query(t.sparql, t) if t.sparql
                end
              else
                specify "#{t.name} #{t.type}"
              end
            end
          end
        end
      end
    end
  end
end