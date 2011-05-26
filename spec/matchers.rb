require 'rdf/isomorphic'
require 'rspec/matchers'
require 'sparql/grammar'

Info = Struct.new(:about, :information, :trace, :compare, :inputDocument, :outputDocument)

def normalize(graph)
  case graph
  when RDF::Graph then graph
  when IO, StringIO
    RDF::Graph.new.load(graph, :base_uri => @info.about)
  else
    # Figure out which parser to use
    g = RDF::Graph.new
    reader_class = detect_format(graph)
    reader_class.new(graph, :base_uri => @info.about).each {|s| g << s}
    g
  end
end

RSpec::Matchers.define :be_equivalent_graph do |expected, info|
  match do |actual|
    @info = if info.respond_to?(:about)
      info
    elsif info.is_a?(Hash)
      identifier = info[:identifier] || expected.is_a?(RDF::Graph) ? expected.context : info[:about]
      trace = info[:trace]
      trace = trace.join("\n") if trace.is_a?(Array)
      Info.new(identifier, info[:information] || "", trace, info[:compare])
    else
      Info.new(expected.is_a?(RDF::Graph) ? expected.context : info, info.to_s)
    end
    @expected = normalize(expected)
    @actual = normalize(actual)
    @actual.isomorphic_with?(@expected)
  end
  
  failure_message_for_should do |actual|
    info = @info.respond_to?(:information) ? @info.information : @info.inspect
    if @expected.is_a?(RDF::Graph) && @actual.size != @expected.size
      "Graph entry count differs:\nexpected: #{@expected.size}\nactual:   #{@actual.size}"
    elsif @expected.is_a?(Array) && @actual.size != @expected.length
      "Graph entry count differs:\nexpected: #{@expected.length}\nactual:   #{@actual.size}"
    else
      "Graph differs"
    end +
    "\n#{info + "\n" unless info.empty?}" +
    (@info.inputDocument ? "Input file: #{@info.inputDocument}\n" : "") +
    (@info.outputDocument ? "Output file: #{@info.outputDocument}\n" : "") +
    "Unsorted Expected:\n#{@expected.dump(:ntriples)}" +
    "Unsorted Results:\n#{@actual.dump(:ntriples)}" +
    (@info.trace ? "\nDebug:\n#{@info.trace}" : "")
  end  
end

RSpec::Matchers.define :produce do |expected, info|
  match do |actual|
    actual.should == expected
  end
  
  failure_message_for_should do |actual|
    "Expected: #{expected.inspect}\n" +
    "Actual: #{actual.inspect}\n" +
    "Processing results:\n#{info.join("\n")}"
  end
end

RSpec::Matchers.define :pass_query do |expected, info|
  match do |actual|
    @expected = expected.read
    query = SPARQL::Grammar.parse(@expected)
    @results = query.execute(actual)

    @results.should == info.expectedResults
  end
  
  failure_message_for_should do |actual|
    information = info.respond_to?(:information) ? info.information : ""
    "#{information + "\n" unless information.empty?}" +
    if @results.nil?
      "Query failed to return results"
    elsif !@results.is_a?(RDF::Literal::Boolean)
      "Query returned non-boolean results"
    elsif info.expectedResults
      "Query returned false"
    else
      "Query returned true (expected false)"
    end +
    "\n#{@expected}" +
    "\nResults:\n#{@actual.dump(:ntriples)}" +
    "\nDebug:\n#{info.trace}"
  end  
end