require 'rdf/isomorphic'
require 'rspec/matchers'
require 'json'

Info = Struct.new(:about, :information, :trace, :inputDocument, :outputDocument, :expectedResults)

def normalize(graph)
  case graph
  when RDF::Enumerable then graph
  when IO, StringIO
    RDF::Graph.new.load(graph, base: @info.about)
  else
    # Figure out which parser to use
    g = RDF::Repository.new
    reader_class = detect_format(graph)
    reader_class.new(graph, base: @info.about).each {|s| g << s}
    g
  end
end

RSpec::Matchers.define :be_equivalent_graph do |expected, info|
  match do |actual|
    @info = if info.respond_to?(:input)
      info
    elsif info.is_a?(Hash)
      identifier = info[:identifier] || info[:about]
      trace = info[:trace]
      trace = trace.join("\n") if trace.is_a?(Array)
      Info.new(identifier, info[:information] || "", trace, info[:inputDocument])
    else
      Info.new(expected.is_a?(RDF::Graph) ? expected.context : info, info.to_s)
    end
    @expected = normalize(expected)
    @actual = normalize(actual)
    @actual.isomorphic_with?(@expected)
  end
  
  failure_message do |actual|
    info = @info.respond_to?(:information) ? @info.information : @info.inspect
    if @expected.is_a?(RDF::Enumerable) && @actual.size != @expected.size
      "Graph entry count differs:\nexpected: #{@expected.size}\nactual:   #{@actual.size}"
    elsif @expected.is_a?(Array) && @actual.size != @expected.length
      "Graph entry count differs:\nexpected: #{@expected.length}\nactual:   #{@actual.size}"
    else
      "Graph differs"
    end +
    "\n#{info + "\n" unless info.empty?}" +
    "Unsorted Expected:\n#{@expected.dump(:nquads, standard_prefixes: true)}" +
    "Unsorted Results:\n#{@actual.dump(:nquads, standard_prefixes: true)}" +
    (@info.inputDocument ? "Input file: #{@info.inputDocument}\n" : "") +
    (@info.outputDocument ? "Output file: #{@info.outputDocument}\n" : "") +
    (@info.trace ? "\nDebug:\n#{@info.trace}" : "")
  end  
end

RSpec::Matchers.define :produce do |expected, info|
  match do |actual|
    expect(actual).to eq expected
  end
  
  failure_message do |actual|
    "Expected: #{expected.is_a?(String) ? expected : expected.to_json(JSON_STATE) rescue 'malformed json'}\n" +
    "Actual  : #{actual.is_a?(String) ? actual : actual.to_json(JSON_STATE) rescue 'malformed json'}\n" +
    #(expected.is_a?(Hash) && actual.is_a?(Hash) ? "Diff: #{expected.diff(actual).to_json(JSON_STATE) rescue 'malformed json'}\n" : "") +
    "Processing results:\n#{info.join("\n")}"
  end
end
