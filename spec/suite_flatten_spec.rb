require_relative 'spec_helper'

unless ENV['CI']
  describe JSON::LD do
    describe "test suite" do
      require_relative 'suite_helper'
      m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}flatten-manifest.jsonld")
      describe m.name do
        m.entries.each do |t|
          t.options[:remap_bnodes] = %w[#t0045].include?(t.property('@id'))

          specify "#{t.property('@id')}: #{t.name} unordered#{' (negative test)' unless t.positiveTest?}" do
            t.options[:ordered] = false
            if %w[#t0005].include?(t.property('@id'))
              expect { t.run self }.to write("Terms beginning with '@' are reserved for future use").to(:error)
            else
              expect { t.run self }.not_to write.to(:error)
            end
          end

          # Skip ordered tests when remapping bnodes
          next if t.options[:remap_bnodes]

          specify "#{t.property('@id')}: #{t.name} ordered#{' (negative test)' unless t.positiveTest?}" do
            t.options[:ordered] = true
            if %w[#t0005].include?(t.property('@id'))
              expect { t.run self }.to write("Terms beginning with '@' are reserved for future use").to(:error)
            else
              expect { t.run self }.not_to write.to(:error)
            end
          end
        end
      end
    end
  end
end
