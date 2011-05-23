# coding: utf-8
$:.unshift "."
require File.join(File.dirname(__FILE__), 'spec_helper')

describe "JSON::LD::Reader" do
  context "discovery" do
    {
      "json"             => RDF::Reader.for(:json),
      "ld"               => RDF::Reader.for(:ld),
      "etc/foaf.json"    => RDF::Reader.for("etc/foaf.json"),
      "etc/foaf.ld"      => RDF::Reader.for("etc/foaf.ld"),
      "foaf.json"        => RDF::Reader.for(:file_name      => "foaf.json"),
      "foaf.ld"          => RDF::Reader.for(:file_name      => "foaf.ld"),
      ".json"            => RDF::Reader.for(:file_extension => "json"),
      ".ld"              => RDF::Reader.for(:file_extension => "ld"),
      "application/json" => RDF::Reader.for(:content_type   => "application/json"),
    }.each_pair do |label, format|
      it "should discover '#{label}'" do
        format.should == JSON::LD::Reader
      end
    end
  end

  context :interface do
    subject { %q({
       "@": "_:bnode1",
       "a": "foaf:Person",
       "foaf:homepage": "http://example.com/bob/",
       "foaf:name": "Bob"
     }) }

    describe "#initialize" do
      it "yields reader given string" do
        inner = mock("inner")
        inner.should_receive(:called).with(JSON::LD::Reader)
        JSON::LD::Reader.new(subject) do |reader|
          inner.called(reader.class)
        end
      end

      it "yields reader given IO" do
        inner = mock("inner")
        inner.should_receive(:called).with(JSON::LD::Reader)
        JSON::LD::Reader.new(StringIO.new(subject)) do |reader|
          inner.called(reader.class)
        end
      end

      it "returns reader" do
        JSON::LD::Reader.new(subject).should be_a(JSON::LD::Reader)
      end
    end

    describe "#each_statement" do
      it "yields statements" do
        inner = mock("inner")
        inner.should_receive(:called).with(RDF::Statement).exactly(3)
        JSON::LD::Reader.new(subject).each_statement do |statement|
          inner.called(statement.class)
        end
      end
    end

    describe "#each_triple" do
      it "yields triples" do
        inner = mock("inner")
        inner.should_receive(:called).exactly(3)
        JSON::LD::Reader.new(subject).each_triple do |subject, predicate, object|
          inner.called(subject.class, predicate.class, object.class)
        end
      end
    end
  end

  context :parsing do
    context "literals" do
      [
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "http://xmlns.com/foaf/0.1/name": "Gregg Kellogg"}),
          %q(<http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg" .)
        ],
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "http://xmlns.com/foaf/0.1/name": "Gregg Kellogg"}),
          %q(<http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg" .)
        ],
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "foaf:name": "Gregg Kellogg"}),
          %q(<http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg" .)
        ],
        [
          %q({"foaf:name": "Gregg Kellogg"}),
          %q(_:a <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg" .)
        ],
        [
          %q({"foaf:name": {"@literal": "Gregg Kellogg"}}),
          %q(_:a <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg" .)
        ],
        [
          %q({"foaf:name": {"@literal": "Gregg Kellogg", "@language": "en-us"}}),
          %q(_:a <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg"@en-us .)
        ],
        [
          %q([{
            "@": "http://greggkellogg.net/foaf.rdf#me",
            "foaf:knows": {"@iri": "http://www.ivan-herman.net/foaf#me"}
          },{
            "@": "http://www.ivan-herman.net/foaf#me",
            "foaf:name": {"@literal": "Herman Iván", "@language": "hu"}
          }]),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.ivan-herman.net/foaf#me> .
            <http://www.ivan-herman.net/foaf#me> <http://xmlns.com/foaf/0.1/name> "Herman Iván"@hu .
          )
        ],
        [
          %q({
            "@":  "http://greggkellogg.net/foaf.rdf#me",
            "dcterms:created":  {"@literal": "1957-02-27", "@datatype": "xsd:date"}
          }),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://purl.org/dc/terms/created> "1957-02-27"^^<http://www.w3.org/2001/XMLSchema#date> .
          )
        ],
      ].each do |(js, nt)|
        it "parses #{js}" do
          parse(js).should be_equivalent_graph(nt, :trace => @debug)
        end
      end
    end


    context "CURIEs" do
      [
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "a": "foaf:Person"}),
          %q(<http://greggkellogg.net/foaf.rdf#me> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .)
        ],
        [
          %q({"@context": {"": "http://example.com/default#"}, ":foo": "bar"}),
          %q(_:a <http://example.com/default#foo> "bar" .)
        ],
      ].each do |(js, nt)|
        it "parses #{js}" do
          parse(js).should be_equivalent_graph(nt, :trace => @debug)
        end
      end
    end

    context "structure" do
      [
        [
          %q({
            "@": "http://greggkellogg.net/foaf.rdf#me",
            "foaf:knows": {
              "@": "http://www.ivan-herman.net/foaf#me",
              "foaf:name": {"@literal": "Herman Iván", "@language": "hu"}
            }
          }),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.ivan-herman.net/foaf#me> .
            <http://www.ivan-herman.net/foaf#me> <http://xmlns.com/foaf/0.1/name> "Herman Iván"@hu .
          )
        ],
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "foaf:knows": ["Manu Sporny", "Ivan Herman"]}),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> "Manu Sporny" .
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> "Ivan Herman" .
          )
        ],
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "foaf:knows": [["Manu Sporny", "Ivan Herman"]]}),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> _:a .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Manu Sporny" .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:b .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Ivan Herman" .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          )
        ],
      ].each do |(js, nt)|
        it "parses #{js}" do
          parse(js).should be_equivalent_graph(nt, :trace => @debug)
        end
      end
    end

    context "lists" do
      [
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "foaf:knows": [[]]}),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          )
        ],
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "foaf:knows": [["Manu Sporny"]]}),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> _:a .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Manu Sporny" .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          )
        ],
        [
          %q({"@": "http://greggkellogg.net/foaf.rdf#me", "foaf:knows": [["Manu Sporny", "Ivan Herman"]]}),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> _:a .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Manu Sporny" .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:b .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Ivan Herman" .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          )
        ],
      ].each do |(js, nt)|
        it "parses #{js}" do
          parse(js).should be_equivalent_graph(nt, :trace => @debug)
        end
      end
    end

    context "context" do
      [
        [
          %q({
            "@context": {
              "@base":  "http://greggkellogg.net/foaf.rdf"
            },
            "@":  "#me",
            "doap:homepage":  {"@iri": "http://github.com/gkellogg/"}
          }),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://usefulinc.com/ns/doap#homepage> <http://github.com/gkellogg/> .
          )
        ],
        [
          %q({
            "@context": {
              "@vocab": "http://usefulinc.com/ns/doap#"
            },
            "@":  "http://greggkellogg.net/foaf.rdf#me",
            "homepage":  {"@iri": "http://github.com/gkellogg/"}
          }),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://usefulinc.com/ns/doap#homepage> <http://github.com/gkellogg/> .
          )
        ],
        [
          %q({
            "@context": {
              "@base":  "http://greggkellogg.net/foaf.rdf",
              "@vocab": "http://usefulinc.com/ns/doap#"
            },
            "@":  "#me",
            "homepage":  {"@iri": "http://github.com/gkellogg/"}
          }),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://usefulinc.com/ns/doap#homepage> <http://github.com/gkellogg/> .
          )
        ],
        [
          %q({
            "@context": {
              "@coerce":  { "xsd:anyURI": "foaf:knows"}
            },
            "@":  "http://greggkellogg.net/foaf.rdf#me",
            "foaf:knows":  "http://www.ivan-herman.net/foaf#me"
          }),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.ivan-herman.net/foaf#me> .
          )
        ],
        [
          %q({
            "@context": {
              "@coerce":  { "xsd:date": "dcterms:created"}
            },
            "@":  "http://greggkellogg.net/foaf.rdf#me",
            "dcterms:created":  "1957-02-27"
          }),
          %q(
            <http://greggkellogg.net/foaf.rdf#me> <http://purl.org/dc/terms/created> "1957-02-27"^^<http://www.w3.org/2001/XMLSchema#date> .
          )
        ],
      ].each do |(js, nt)|
        it "parses #{js}" do
          parse(js).should be_equivalent_graph(nt, :trace => @debug)
        end
      end
    end

    context "advanced features" do
      [
        [
          %q({"@context": { "measure": "http://example/measure#"}, "measure:cups": 5.3}),
          %q(_:a <http://example/measure#cups> "5.3"^^<http://www.w3.org/2001/XMLSchema#double> .)
        ],
        [
          %q({"@context": { "measure": "http://example/measure#"}, "measure:cups": 5.3e0}),
          %q(_:a <http://example/measure#cups> "5.3"^^<http://www.w3.org/2001/XMLSchema#double> .)
        ],
        [
          %q({"@context": { "chem": "http://example/chem#"}, "chem:protons": 12}),
          %q(_:a <http://example/chem#protons> "12"^^<http://www.w3.org/2001/XMLSchema#integer> .)
        ],
        [
          %q({"@context": { "sensor": "http://example/sensor#"}, "sensor:active": true}),
          %q(_:a <http://example/sensor#active> "true"^^<http://www.w3.org/2001/XMLSchema#boolean> .)
        ],
      ].each do |(js, nt)|
        it "parses #{js}" do
          parse(js).should be_equivalent_graph(nt, :trace => @debug)
        end
      end
    end
  end

  def parse(input, options = {})
    @debug = []
    graph = options[:graph] || RDF::Graph.new
    graph << JSON::LD::Reader.new(input, {:debug => @debug, :validate => true, :canonicalize => false}.merge(options))
  end
end
