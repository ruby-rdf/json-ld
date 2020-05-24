# coding: utf-8
require_relative 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require_relative 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}toRdf-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('@id')}: #{t.name}#{' (negative test)' unless t.positiveTest?}" do
          pending "Generalized RDF" if t.options[:produceGeneralizedRdf]
          pending "RDF*" if t.property('@id') == '#te122'
          if %w(#t0118).include?(t.property('@id'))
            expect {t.run self}.to write(/Statement .* is invalid/).to(:error)
          elsif %w(#te075).include?(t.property('@id'))
            expect {t.run self}.to write(/is invalid/).to(:error)
          elsif %w(#te005 #tpr34 #tpr35 #tpr36 #tpr37 #tpr38 #tpr39 #te119 #te120).include?(t.property('@id'))
            expect {t.run self}.to write("beginning with '@' are reserved for future use").to(:error)
          elsif %w(#te068).include?(t.property('@id'))
            expect {t.run self}.to write("[DEPRECATION]").to(:error)
          elsif %w(#twf05).include?(t.property('@id'))
            expect {t.run self}.to write("@language must be valid BCP47").to(:error)
          else
            expect {t.run self}.not_to write.to(:error)
          end
        end
      end
    end
  end
end unless ENV['CI']