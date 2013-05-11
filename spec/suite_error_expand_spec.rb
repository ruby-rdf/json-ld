# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}tests/error-expand-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('input')}: #{t.name}" do
          begin
            t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
            t.debug << "context: #{t.context.read}" if t.property('context')
            lambda {
              JSON::LD::API.expand(t.input, nil, :base => t.base, :validate => true)
            }.should raise_error
          end
        end
      end
    end
  end
end unless ENV['CI']