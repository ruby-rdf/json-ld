require 'rdf/isomorphic'
require 'rspec/matchers'
require 'json'

Info = Struct.new(:about, :information, :trace, :inputDocument, :outputDocument, :expectedResults)

def normalize(graph)
  case graph
  when RDF::Graph then graph
  when IO, StringIO
    RDF::Graph.new.load(graph, :base => @info.about)
  else
    # Figure out which parser to use
    g = RDF::Graph.new
    reader_class = detect_format(graph)
    reader_class.new(graph, :base => @info.about).each {|s| g << s}
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
      Info.new(identifier, info[:information] || "", trace, info[:inputDocument])
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
    "Unsorted Expected:\n#{@expected.dump(:nquads, :standard_prefixes => true)}" +
    "Unsorted Results:\n#{@actual.dump(:nquads, :standard_prefixes => true)}" +
    (@info.inputDocument ? "Input file: #{@info.inputDocument}\n" : "") +
    (@info.outputDocument ? "Output file: #{@info.outputDocument}\n" : "") +
    (@info.trace ? "\nDebug:\n#{@info.trace}" : "")
  end  
end

RSpec::Matchers.define :produce do |expected, info|
  match do |actual|
    actual.should == expected
  end
  
  failure_message_for_should do |actual|
    "Expected: #{expected.is_a?(String) ? expected : expected.to_json(JSON_STATE)}\n" +
    "Actual  : #{actual.is_a?(String) ? actual : actual.to_json(JSON_STATE)}\n" +
    "Inspect : #{actual.inspect}\n" + 
    "Processing results:\n#{info.join("\n")}"
  end
end

RSpec::Matchers.define :pass_query do |expected, info|
  match do |actual|
    if info.respond_to?(:information)
      @info = info
    elsif info.is_a?(Hash)
      trace = info[:trace]
      trace = trace.join("\n") if trace.is_a?(Array)
      @info = Info.new(info[:about] || info[:inputDocument] || "", info[:information] || "", trace, info[:inputDocument])
      @info[:expectedResults] = info[:expectedResults] || RDF::Literal::Boolean.new(true)
    elsif info.is_a?(Array)
      @info = Info.new()
      @info[:trace] = info.join("\n")
      @info[:expectedResults] = RDF::Literal::Boolean.new(true)
    else
      @info = Info.new()
      @info[:expectedResults] = RDF::Literal::Boolean.new(true)
    end

    @expected = expected.respond_to?(:read) ? expected.read : expected
    @expected = @expected.force_encoding("utf-8") if @expected.respond_to?(:force_encoding)

    require 'sparql'
    query = SPARQL.parse(@expected)
    actual = actual.force_encoding("utf-8") if actual.respond_to?(:force_encoding)
    @results = query.execute(actual)
    @results.should == @info.expectedResults
  end
  
  failure_message_for_should do |actual|
    "#{@info.inspect + "\n"}" +
    "#{@info.name + "\n" if @info.name}" +
    if @results.nil?
      "Query failed to return results"
    elsif !@results.is_a?(RDF::Literal::Boolean)
      "Query returned non-boolean results"
    elsif @info.expectedResults != @results
      "Query returned false (expected #{@info.expectedResults})"
    else
      "Query returned true (expected #{@info.expectedResults})"
    end +
    "\n#{@expected}" +
    "\nResults:\n#{@actual.dump(:ttl, :standard_prefixes => true)}" +
    (@info.inputDocument ? "\nInput file: #{@info.input.read}\n" : "") +
    "\nDebug:\n#{@info.trace}"
  end  
end
