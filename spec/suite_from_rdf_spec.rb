require_relative 'spec_helper'

unless ENV['CI']
  describe JSON::LD do
    describe "test suite" do
      require_relative 'suite_helper'
      m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}fromRdf-manifest.jsonld")
      describe m.name do
        m.entries.each do |t|
          specify "#{t.property('@id')}: #{t.name} unordered#{' (negative test)' unless t.positiveTest?}" do
            t.options[:ordered] = false
            expect { t.run self }.not_to write.to(:error)
          end

          specify "#{t.property('@id')}: #{t.name} ordered#{' (negative test)' unless t.positiveTest?}" do
            t.options[:ordered] = true
            expect { t.run self }.not_to write.to(:error)
          end
        end
      end
    end
  end
end
