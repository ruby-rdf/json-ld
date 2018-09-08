require 'rspec/matchers' # @see http://rubygems.org/gems/rspec
require_relative 'support/extensions'

RSpec::Matchers.define :produce_jsonld do |expected, logger|
  match do |actual|
    expect(actual).to be_equivalent_jsonld expected
  end

  failure_message do |actual|
    "Expected: #{expected.is_a?(String) ? expected : expected.to_json(JSON_STATE) rescue 'malformed json'}\n" +
    "Actual  : #{actual.is_a?(String) ? actual : actual.to_json(JSON_STATE) rescue 'malformed json'}\n" +
    "\nDebug:\n#{logger}"
  end

  failure_message_when_negated do |actual|
    "Expected not to produce the following:\n" + 
    "Actual  : #{actual.is_a?(String) ? actual : actual.to_json(JSON_STATE) rescue 'malformed json'}\n" +
    "\nDebug:\n#{logger}"
  end
end
