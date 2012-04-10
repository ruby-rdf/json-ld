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
            next if t.is_a?(Fixtures::JSONLDTest::NormalizeTest)
            specify "#{File.basename(t.inputDocument.to_s)}: #{t.name}" do
              begin
                t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
                case t
                when Fixtures::JSONLDTest::CompactTest
                  t.debug << "context: #{t.extra.read}" if t.extraDocument
                  result = JSON::LD::API.compact(t.input, t.extra, nil,
                                                :base_uri => t.inputDocument,
                                                :debug => t.debug)
                  expected = JSON.load(t.expect)
                  result.should produce(expected, t.debug)
                when Fixtures::JSONLDTest::ExpandTest
                  t.debug << "context: #{t.extra.read}" if t.extraDocument
                  result = JSON::LD::API.expand(t.input, nil,
                                                :base_uri => t.inputDocument,
                                                :debug => t.debug)
                  expected = JSON.load(t.expect)
                  result.should produce(expected, t.debug)
                when Fixtures::JSONLDTest::FrameTest
                  t.debug << "frame: #{t.extra.read}" if t.extraDocument
                  result = JSON::LD::API.frame(t.input, t.extra,
                                                :base_uri => t.inputDocument,
                                                :debug => t.debug)
                  expected = JSON.load(t.expect)
                  result.should produce(expected, t.debug)
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
              rescue JSON::LD::ProcessingError => e
                fail("Processing error: #{e.message}")
              rescue JSON::LD::InvalidContext => e
                fail("Invalid Context: #{e.message}")
              rescue JSON::LD::InvalidFrame => e
                fail("Invalid Frame: #{e.message}")
              end
            end
          end
        end
      end
    end
  end
end