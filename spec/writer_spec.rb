# coding: utf-8
$:.unshift "."
require File.join(File.dirname(__FILE__), 'spec_helper')

describe JSON::LD::Writer do
  describe "simple tests" do
    it "should use full URIs without base" do
      input = %(<http://a/b> <http://a/c> <http://a/d> .)
      serialize(input).should produce({
        "@" => "http://a/b",
        "http://a/c" => {:iri => "http://a/d"}
      }, @debug)
    end

    it "should use relative URIs with base" do
      input = %(<http://a/b> <http://a/c> <http://a/d> .)
      serialize(input, :base_uri => "http://a/").should produce({
        "@context" => {"@base" => "http://a/"},
        "@"        => "b",
        "http://a/c" => {:iri => "d"}
      }, @debug)
    end

    it "should use coerced relative URIs with base" do
      input = %(<http://a/b> <http://a/c> <http://a/d> .)
      serialize(input,
        :base_uri => "http://a/",
        :coerce => {RDF::URI("http://a/c") => RDF::XSD.anyURI}).
      should produce({
        "@context" => {"@base" => "http://a/", "@coerce" => {"xsd:anyURI" => "c"}},
        "@"        => "b",
        "http://a/c" => "d"
      }, @debug)
    end

    it "should use qname URIs with prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      serialize(input)
    end

    it "should use qname URIs with empty prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      serialize(input, :prefixes => { "" => RDF::FOAF}
      )
    end
    
    # see example-files/arnau-registered-vocab.rb
    it "should use qname URIs with empty suffix" do
      input = %(<http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> .)
      serialize(input, :prefixes => {"foaf" => RDF::FOAF})
    end
    
    it "should not use qname with illegal local part" do
      input = %(
        @prefix db: <http://dbpedia.org/resource/> .
        @prefix dbo: <http://dbpedia.org/ontology/> .
        db:Michael_Jackson dbo:artistOf <http://dbpedia.org/resource/%28I_Can%27t_Make_It%29_Another_Day> .
      )

      serialize(input, :prefixes => {
          "db" => RDF::URI("http://dbpedia.org/resource/"),
          "dbo" => RDF::URI("http://dbpedia.org/ontology/")})
    end

    it "should order properties" do
      input = %(
        @prefix : <http://xmlns.com/foaf/0.1/> .
        @prefix dc: <http://purl.org/dc/elements/1.1/> .
        @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
        :b :c :d .
        :b dc:title "title" .
        :b a :class .
        :b rdfs:label "label" .
      )
      serialize(input, :prefixes => {
        "" => RDF::FOAF,
        :dc => "http://purl.org/dc/elements/1.1/",
        :rdfs => RDF::RDFS})
    end
    
    it "should generate object list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :b :c :d, :e .)
      serialize(input, :prefixes => {"" => RDF::FOAF})
    end
    
    it "should generate property list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :b :c :d; :e :f .)
      serialize(input, :prefixes => {"" => RDF::FOAF})
    end
  end
  
  def parse(input, options = {})
    RDF::Graph.new << RDF::NTriples::Reader.new(input, options)
  end

  # Serialize ntstr to a string and compare against regexps
  def serialize(ntstr, options = {})
    g = parse(ntstr, options)
    @debug = [] << g.dump(:ttl)
    result = JSON::LD::Writer.hash(options.merge(:debug => @debug)) do |writer|
      writer << g
    end
    if $verbose
      #puts hash.to_json
    end
    
    result
  end
end
