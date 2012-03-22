# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/writer'

describe JSON::LD::API do
  describe ".fromTriples" do
    context "simple tests" do
      it "One subject IRI object" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        serialize(input).should produce([
        {
          '@id'         => "http://a/b",
          "http://a/c"  => {"@id" => "http://a/d"}
        }], @debug)
      end

      it "should order literal values" do
        input = %(@base <http://a/> . <b> <c> "e", "d" .)
        serialize(input).
        should produce([{
          '@id'       => "http://a/b",
          "http://a/c"  => [
            {"@value" => "d"},
            {"@value" => "e"}
          ]
        }], @debug)
      end

      it "should order URI values" do
        input = %(@base <http://a/> . <b> <c> <e>, <d> .)
        serialize(input).
        should produce([{
          '@id'         => "http://a/b",
          "http://a/c"  => [
            {"@id" => "http://a/d"},
            {"@id" => "http://a/e"}
          ]
        }], @debug)
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
        serialize(input).
        should produce([{
          '@id'                                       => "http://xmlns.com/foaf/0.1/b",
          '@type'                                     => "http://xmlns.com/foaf/0.1/class",
          "http://purl.org/dc/elements/1.1/title"     => {"@value" => "title"},
          "http://www.w3.org/2000/01/rdf-schema#label"=> {"@value" => "label"},
          "http://xmlns.com/foaf/0.1/c"               => {"@id" => "http://xmlns.com/foaf/0.1/d"}
        }], @debug)
      end
    
      it "should generate object list" do
        input = %(@prefix : <http://example.com/> . :b :c :d, :e .)
        serialize(input).
        should produce([{
          '@id'                         => "http://example.com/b",
          "http://example.com/c" => [
            {"@id" => "http://example.com/d"},
            {"@id" => "http://example.com/e"}
          ]
        }], @debug)
      end
    
      it "should generate property list" do
        input = %(@prefix : <http://example.com/> . :b :c :d; :e :f .)
        serialize(input).
        should produce([{
          '@id'   => "http://example.com/b",
          "http://example.com/c"      => {"@id" => "http://example.com/d"},
          "http://example.com/e"      => {"@id" => "http://example.com/f"}
        }], @debug)
      end
    
      it "serializes multiple subjects" do
        input = %q(
          @prefix : <http://www.w3.org/2006/03/test-description#> .
          @prefix dc: <http://purl.org/dc/elements/1.1/> .
          <test-cases/0001> a :TestCase .
          <test-cases/0002> a :TestCase .
        )
        serialize(input).
        should produce([
          {'@id'  => "test-cases/0001", '@type' => "http://www.w3.org/2006/03/test-description#TestCase"},
          {'@id'  => "test-cases/0002", '@type' => "http://www.w3.org/2006/03/test-description#TestCase"}
        ], @debug)
      end
    end
  
    context "literals" do
      it "coerces typed literal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"^^ex:d .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => {"@value" => "foo", "@type" => "http://example.com/d"}
        }], @debug)
      end

      it "coerces integer" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => {"@value" => "1", "@type" => "http://www.w3.org/2001/XMLSchema#integer"}
        }], @debug)
      end

      it "coerces boolean" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b true .)
        serialize(input,).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => true
        }], @debug)
      end

      it "coerces decmal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => {"@value" => "1.0", "@type" => "http://www.w3.org/2001/XMLSchema#decimal"}
        }], @debug)
      end

      it "coerces double" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0e0 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => {"@value" => "1.0E0", "@type" => "http://www.w3.org/2001/XMLSchema#double"}
        }], @debug)
      end
    
      it "encodes language literal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"@en-us .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => {"@value" => "foo", "@language" => "en-us"}
        }], @debug)
      end
    end

    context "anons" do
      it "should generate bare anon" do
        input = %(@prefix : <http://example.com/> . _:a :a :b .)
        serialize(input).should produce([{
          "@id" => "_:a",
          "http://example.com/a"  => {"@id" => "http://example.com/b"}
        }], @debug)
      end
    
      it "should generate anon as object" do
        input = %(@prefix : <http://example.com/> . :a :b _:a . _:a :c :d .)
        serialize(input).should produce([
          {
            "@id" => "http://example.com/a",
            "http://example.com/b"  => {"@id" => "_:a"}
          },
          {
            "@id" => "_:a",
            "http://example.com/c"  => {"@id" => "http://example.com/d"}
          },
        ], @debug)
      end
    end
  
    context "lists" do
      it "should generate literal list" do
        input = %(
          @prefix : <http://example.com/> .
          @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
          :a :b ("apple" "banana")  .
        )
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => {
            "@list" => [
              {"@value" => "apple"},
              {"@value" => "banana"}
            ]
          }
        }], @debug)
      end
    
      it "should generate iri list" do
        input = %(@prefix : <http://example.com/> . :a :b (:c) .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => {
            "@list" => [
              {"@id" => "http://example.com/c"}
            ]
          }
        }], @debug)
      end
    
      it "should generate empty list" do
        input = %(@prefix : <http://example.com/> . :a :b () .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => {"@list" => []}
        }], @debug)
      end
    
      it "should generate single element list" do
        input = %(@prefix : <http://example.com/> . :a :b ( "apple" ) .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => {"@list" => [{"@value" => "apple"}]}
        }], @debug)
      end
    
      it "should generate single element list without @type" do
        input = %(
        @prefix : <http://example.com/> . :a :b ( _:a ) . _:a :b "foo" .)
        serialize(input).should produce([
          {
            '@id'   => "http://example.com/a",
            "http://example.com/b"  => {"@list" => [{"@id" => "_:a"}]}
          },
          {
            '@id'   => "_:a",
            "http://example.com/b"  => {"@value" => "foo"}
          }
        ], @debug)
      end
    end
  end

  def parse(input, options = {})
    RDF::Graph.new << RDF::Turtle::Reader.new(input, options)
  end

  # Serialize ntstr to a string and compare against regexps
  def serialize(ntstr, options = {})
    g = ntstr.is_a?(String) ? parse(ntstr, options) : ntstr
    @debug = [] << g.dump(:ttl)
    triples = g.each_statement.to_a.sort_by {|s| s.to_ntriples }
    JSON::LD::API.fromTriples(triples, options.merge(:debug => @debug))
  end
end
