# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require 'suite_helper'
    
    m = Fixtures::JSONLDTest::Manifest.each.to_a.first
    describe m.name do
      m.entries.each do |m2|
        describe m2.name do
          m2.entries.each do |t|
            next unless t.is_a?(Fixtures::JSONLDTest::CompactTest)
            specify "#{File.basename(t.inputDocument.to_s)}: #{t.name}" do
              t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
              t.debug << "extra: #{t.extra.read}" if t.extraDocument
              #debugger
              case t
              when Fixtures::JSONLDTest::CompactTest
                result = JSON::LD::API.compact(t.input, t.extra,
                                              :base_uri => t.inputDocument,
                                              :debug => t.debug)
                expected = JSON.load(t.expect)
                result.should produce(expected, t.debug)
              when Fixtures::JSONLDTest::ExpandTest
                result = JSON::LD::API.expand(t.input, nil,
                                              :base_uri => t.inputDocument,
                                              :debug => t.debug)
                expected = JSON.load(t.expect)
                result.should produce(expected, t.debug)
              when Fixtures::JSONLDTest::FrameTest
                pending("Framing")
              when Fixtures::JSONLDTest::NormalizeTest
                pending("Normalization")
              when Fixtures::JSONLDTest::RDFTest
                reader = RDF::Reader.open(t.inputDocument,
                  :base_uri => t.inputDocument,
                  :debug => t.debug,
                  :format => :jsonld)
                reader.should be_a JSON::LD::Reader

                graph = RDF::Graph.new << reader
                graph.should pass_query(t.sparql, t) if t.sparql
              else
                pending("unkown test type #{t.inspect}")
              end
            end
          end
        end
      end
    end
  end
end