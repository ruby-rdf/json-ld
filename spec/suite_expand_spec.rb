# coding: utf-8
require_relative 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require_relative 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}expand-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        # MultiJson use OJ, by default, which doesn't handle native numbers the same as the JSON gem.
        t.options[:adapter] = :json_gem if %w(#tjs12).include?(t.property('@id'))
        specify "#{t.property('@id')}: #{t.name} unordered#{' (negative test)' unless t.positiveTest?}" do
          t.options[:ordered] = false
          if %w(#t0068).include?(t.property('@id'))
            expect{t.run self}.to write("[DEPRECATION]").to(:error)
          elsif %w(#t0005 #tpr34 #tpr35 #tpr36 #tpr37 #t0119 #t0120).include?(t.property('@id'))
            expect{t.run self}.to write("beginning with '@' are reserved for future use").to(:error)
          else
            expect {t.run self}.not_to write.to(:error)
          end
        end

        specify "#{t.property('@id')}: #{t.name} ordered#{' (negative test)' unless t.positiveTest?}" do
          t.options[:ordered] = true
          if %w(#t0068).include?(t.property('@id'))
            expect{t.run self}.to write("[DEPRECATION]").to(:error)
          elsif %w(#t0005 #tpr34 #tpr35 #tpr36 #tpr37 #t0119 #t0120).include?(t.property('@id'))
            expect{t.run self}.to write("beginning with '@' are reserved for future use").to(:error)
          else
            expect {t.run self}.not_to write.to(:error)
          end
        end
      end
    end
  end
end unless ENV['CI']