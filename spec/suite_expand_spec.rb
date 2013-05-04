# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open('http://json-ld.org/test-suite/tests/expand-manifest.jsonld')
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('input')}: #{t.name}" do
          case t.property('input')
          when /(0069|0070|0071|0072)/
            pending "Contridiction on cyclical term definition from commit 657c90f3fc4050fce006fa11a2a420e7e4efe049"
          end
          begin
            t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
            t.debug << "context: #{t.context.read}" if t.property('context')
            result = JSON::LD::API.expand(t.input, nil, nil,
                                          :base => t.base,
                                          :debug => t.debug)
            expected = JSON.load(t.expect)
            result.should produce(expected, t.debug)
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