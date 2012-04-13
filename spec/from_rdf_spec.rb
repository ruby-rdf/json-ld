# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/writer'
require 'rdf/trig'

describe JSON::LD::API do
  describe ".fromRDF" do
    context "simple tests" do
      it "One subject IRI object" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        serialize(input).should produce([
        {
          '@id'         => "http://a/b",
          "http://a/c"  => [{"@id" => "http://a/d"}]
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
          "http://example.com/c"      => [{"@id" => "http://example.com/d"}],
          "http://example.com/e"      => [{"@id" => "http://example.com/f"}]
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
          {'@id'  => "test-cases/0001", '@type' => ["http://www.w3.org/2006/03/test-description#TestCase"]},
          {'@id'  => "test-cases/0002", '@type' => ["http://www.w3.org/2006/03/test-description#TestCase"]}
        ], @debug)
      end
    end
  
    context "literals" do
      it "coerces typed literal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"^^ex:d .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [{"@value" => "foo", "@type" => "http://example.com/d"}]
        }], @debug)
      end

      it "coerces integer" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [1]
        }], @debug)
      end

      it "coerces boolean" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b true .)
        serialize(input,).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [true]
        }], @debug)
      end

      it "coerces decmal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [{"@value" => "1.0", "@type" => "http://www.w3.org/2001/XMLSchema#decimal"}]
        }], @debug)
      end

      it "coerces double" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0e0 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [1.0E0]
        }], @debug)
      end
    
      it "encodes language literal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"@en-us .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [{"@value" => "foo", "@language" => "en-us"}]
        }], @debug)
      end
    end

    context "anons" do
      it "should generate bare anon" do
        input = %(@prefix : <http://example.com/> . _:a :a :b .)
        serialize(input).should produce([{
          "@id" => "_:t0",
          "http://example.com/a"  => [{"@id" => "http://example.com/b"}]
        }], @debug)
      end
    
      it "should generate anon as object" do
        input = %(@prefix : <http://example.com/> . :a :b _:a . _:a :c :d .)
        serialize(input).should produce([
          {
            "@id" => "http://example.com/a",
            "http://example.com/b"  => [{"@id" => "_:t0"}]
          },
          {
            "@id" => "_:t0",
            "http://example.com/c"  => [{"@id" => "http://example.com/d"}]
          }
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
            "http://example.com/b"  => {"@list" => [{"@id" => "_:t1"}]}
          },
          {
            '@id'   => "_:t1",
            "http://example.com/b"  => [{"@value" => "foo"}]
          },
        ], @debug)
      end
    end
    
    context "quads" do
      {
        "simple named graph" => {
          :input => %(
            @prefix : <http://example.com/> .
            :U { :a :b :c .}
          ),
          :output => [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => [{"@id" => "http://example.com/c"}]
              }]
            }
          ]
        },
        "with properties" => {
          :input => %(
            @prefix : <http://example.com/> .
            :U { :a :b :c .}
            { :U :d :e .}
          ),
          :output => [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => [{"@id" => "http://example.com/c"}]
              }],
              "http://example.com/d" => [{"@id" => "http://example.com/e"}]
            }
          ]
        },
        "with lists" => {
          :input => %(
            @prefix : <http://example.com/> .
            :U { :a :b (:c) .}
            { :U :d (:e) .}
          ),
          :output => [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => {"@list" => [{"@id" => "http://example.com/c"}]}
              }],
              "http://example.com/d" => {"@list" => [{"@id" => "http://example.com/e"}]}
            }
          ]
        },
      }.each_pair do |name, properties|
        it name do
          r = serialize(properties[:input], :reader => RDF::TriG::Reader)
          r.should produce(properties[:output], @debug)
        end
      end
    end
  end

  def parse(input, options = {})
    reader = options[:reader] || RDF::Turtle::Reader
    RDF::Repository.new << reader.new(input, options)
  end

  # Serialize ntstr to a string and compare against regexps
  def serialize(ntstr, options = {})
    g = ntstr.is_a?(String) ? parse(ntstr, options) : ntstr
    @debug = [] << g.dump(:trig)
    statements = g.each_statement.to_a
    JSON::LD::API.fromRDF(statements, nil, options.merge(:debug => @debug))
  end
end
