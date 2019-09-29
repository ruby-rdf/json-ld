# coding: utf-8
require_relative 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require_relative 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::FRAME_SUITE}frame-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('@id')}: #{t.name} unordered#{' (negative test)' unless t.positiveTest?}" do
          t.options[:ordered] = false
          expect {t.run self}.not_to write.to(:error)
        end

        specify "#{t.property('@id')}: #{t.name} ordered#{' (negative test)' unless t.positiveTest?}" do
          pending "Ordered version of in03" if %w(#tin03).include?(t.property('@id'))
          t.options[:ordered] = true
          expect {t.run self}.not_to write.to(:error)
        end
      end
    end
  end
end unless ENV['CI']