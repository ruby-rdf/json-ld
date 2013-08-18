# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}tests/toRdf-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('input')}: #{t.name}" do
          begin
            t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
            quads = JSON::LD::API.toRDF(t.input, nil,
                                        :base => t.base,
                                        :debug => t.debug
            ).map do |statement|
              t.to_quad(statement)
            end

            sorted_expected = t.expect.readlines.uniq.sort.join("")
            quads.uniq.sort.join("").should produce(sorted_expected, t.debug)
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
end unless ENV['CI']