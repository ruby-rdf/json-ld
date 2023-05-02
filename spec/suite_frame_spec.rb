require_relative 'spec_helper'

unless ENV['CI']
  describe JSON::LD do
    describe "test suite" do
      require_relative 'suite_helper'
      m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::FRAME_SUITE}frame-manifest.jsonld")
      describe m.name do
        m.entries.each do |t|
          t.options[:remap_bnodes] = %w[#t0021 #tp021].include?(t.property('@id'))

          specify "#{t.property('@id')}: #{t.name} unordered#{' (negative test)' unless t.positiveTest?}" do
            t.options[:ordered] = false
            expect { t.run self }.not_to write.to(:error)
          end

          # Skip ordered tests when remapping bnodes
          next if t.options[:remap_bnodes]

          specify "#{t.property('@id')}: #{t.name} ordered#{' (negative test)' unless t.positiveTest?}" do
            t.options[:ordered] = true
            pending("changes due to blank node reordering") if %w[#tp021].include?(t.property('@id'))
            expect { t.run self }.not_to write.to(:error)
          end
        end
      end
    end
  end
end
