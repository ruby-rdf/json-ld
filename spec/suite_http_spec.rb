require_relative 'spec_helper'
require 'rack/test'

begin
  unless ENV['CI']
    describe JSON::LD do
      describe "test suite" do
        require_relative 'suite_helper'
        m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}http-manifest.jsonld")
        describe m.name do
          include Rack::Test::Methods
          before(:all) { JSON::LD::Writer.default_context = "#{Fixtures::SuiteTest::SUITE}http/default-context.jsonld" }
          after(:all) { JSON::LD::Writer.default_context = nil }

          let(:app) do
            JSON::LD::ContentNegotiation.new(
              double("Target Rack Application", :call => [200, {}, @results]),
              {}
            )
          end

          m.entries.each do |t|
            specify "#{t.property('@id')}: #{t.name} unordered#{' (negative test)' unless t.positiveTest?}" do
              t.options[:ordered] = false
              expect { t.run self }.not_to write.to(:error)
            end
          end
        end
      end
    end
  end
rescue IOError
  # Skip this until such a test suite is re-added
end
