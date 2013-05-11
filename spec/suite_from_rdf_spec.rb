# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}tests/fromRdf-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('input')}: #{t.name}" do
          begin
            t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
            t.input.rewind
            t.debug << "result: #{t.expect.read}"
            repo = RDF::Repository.load(t.base)
            t.debug << "repo: #{repo.dump(t.id == '#t0012' ? :nquads : :trig)}"
            result = JSON::LD::API.fromRDF(repo.each_statement.to_a,
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