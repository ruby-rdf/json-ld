# coding: utf-8
require_relative 'spec_helper'
require 'rdf/spec/writer'

describe JSON::LD::API do
  let(:logger) {RDF::Spec.logger}

  describe ".fromRdf" do
    context "simple tests" do
      it "One subject IRI object" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        expect(serialize(input)).to produce_jsonld([
        {
          '@id'         => "http://a/b",
          "http://a/c"  => [{"@id" => "http://a/d"}]
        }
        ], logger)
      end

      it "should generate object list" do
        input = %(@prefix : <http://example.com/> . :b :c :d, :e .)
        expect(serialize(input)).
        to produce_jsonld([{
          '@id'                         => "http://example.com/b",
          "http://example.com/c" => [
            {"@id" => "http://example.com/d"},
            {"@id" => "http://example.com/e"}
          ]
        }
        ], logger)
      end
    
      it "should generate property list" do
        input = %(@prefix : <http://example.com/> . :b :c :d; :e :f .)
        expect(serialize(input)).
        to produce_jsonld([{
          '@id'   => "http://example.com/b",
          "http://example.com/c"      => [{"@id" => "http://example.com/d"}],
          "http://example.com/e"      => [{"@id" => "http://example.com/f"}]
        }
        ], logger)
      end
    
      it "serializes multiple subjects" do
        input = %q(
          @prefix : <http://www.w3.org/2006/03/test-description#> .
          @prefix dc: <http://purl.org/dc/elements/1.1/> .
          <test-cases/0001> a :TestCase .
          <test-cases/0002> a :TestCase .
        )
        expect(serialize(input)).
        to produce_jsonld([
          {'@id'  => "test-cases/0001", '@type' => ["http://www.w3.org/2006/03/test-description#TestCase"]},
          {'@id'  => "test-cases/0002", '@type' => ["http://www.w3.org/2006/03/test-description#TestCase"]},
        ], logger)
      end
    end
  
    context "literals" do
      context "coercion" do
        it "typed literal" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"^^ex:d .)
          expect(serialize(input)).to produce_jsonld([
            {
              '@id'   => "http://example.com/a",
              "http://example.com/b"    => [{"@value" => "foo", "@type" => "http://example.com/d"}]
            }
          ], logger)
        end

        it "integer" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1 .)
          expect(serialize(input, useNativeTypes: true)).to produce_jsonld([{
            '@id'   => "http://example.com/a",
            "http://example.com/b"    => [{"@value" => 1}]
          }], logger)
        end

        it "integer (non-native)" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1 .)
          expect(serialize(input, useNativeTypes: false)).to produce_jsonld([{
            '@id'   => "http://example.com/a",
            "http://example.com/b"    => [{"@value" => "1","@type" => "http://www.w3.org/2001/XMLSchema#integer"}]
          }], logger)
        end

        it "boolean" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b true .)
          expect(serialize(input, useNativeTypes: true)).to produce_jsonld([{
            '@id'   => "http://example.com/a",
            "http://example.com/b"    => [{"@value" => true}]
          }], logger)
        end

        it "boolean (non-native)" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b true .)
          expect(serialize(input, useNativeTypes: false)).to produce_jsonld([{
            '@id'   => "http://example.com/a",
            "http://example.com/b"    => [{"@value" => "true","@type" => "http://www.w3.org/2001/XMLSchema#boolean"}]
          }], logger)
        end

        it "decmal" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0 .)
          expect(serialize(input, useNativeTypes: true)).to produce_jsonld([{
            '@id'   => "http://example.com/a",
            "http://example.com/b"    => [{"@value" => "1.0", "@type" => "http://www.w3.org/2001/XMLSchema#decimal"}]
          }], logger)
        end

        it "double" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0e0 .)
          expect(serialize(input, useNativeTypes: true)).to produce_jsonld([{
            '@id'   => "http://example.com/a",
            "http://example.com/b"    => [{"@value" => 1.0E0}]
          }], logger)
        end

        it "double (non-native)" do
          input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0e0 .)
          expect(serialize(input, useNativeTypes: false)).to produce_jsonld([{
            '@id'   => "http://example.com/a",
            "http://example.com/b"    => [{"@value" => "1.0E0","@type" => "http://www.w3.org/2001/XMLSchema#double"}]
          }], logger)
        end
      end

      context "datatyped (non-native)" do
        {
          integer:            1,
          unsignedInteger:    1,
          nonNegativeInteger: 1,
          float:              1,
          nonPositiveInteger: -1,
          negativeInteger:    -1,
        }.each do |t, v|
          it "#{t}" do
            input = %(
              @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
              @prefix ex: <http://example.com/> .
              ex:a ex:b "#{v}"^^xsd:#{t} .
            )
            expect(serialize(input, useNativeTypes: false)).to produce_jsonld([{
              '@id'   => "http://example.com/a",
              "http://example.com/b"    => [{"@value" => "#{v}","@type" => "http://www.w3.org/2001/XMLSchema##{t}"}]
            }], logger)
          end
        end
      end

      it "encodes language literal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"@en-us .)
        expect(serialize(input)).to produce_jsonld([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [{"@value" => "foo", "@language" => "en-us"}]
        }], logger)
      end
    end

    context "anons" do
      it "should generate bare anon" do
        input = %(@prefix : <http://example.com/> . _:a :a :b .)
        expect(serialize(input)).to produce_jsonld([
        {
          "@id" => "_:a",
          "http://example.com/a"  => [{"@id" => "http://example.com/b"}]
        }
        ], logger)
      end
    
      it "should generate anon as object" do
        input = %(@prefix : <http://example.com/> . :a :b _:a . _:a :c :d .)
        expect(serialize(input)).to produce_jsonld([
          {
            "@id" => "_:a",
            "http://example.com/c"  => [{"@id" => "http://example.com/d"}]
          },
          {
            "@id" => "http://example.com/a",
            "http://example.com/b"  => [{"@id" => "_:a"}]
          }
        ], logger)
      end
    end

    context "lists" do
      {
        "literal list" => {
          input: %q(
            @prefix : <http://example.com/> .
            @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
            :a :b ("apple" "banana")  .
          ),
          output: [{
            '@id'   => "http://example.com/a",
            "http://example.com/b"  => [{
              "@list" => [
                {"@value" => "apple"},
                {"@value" => "banana"}
              ]
            }]
          }]
        },
        "iri list" => {
          input: %q(@prefix : <http://example.com/> . :a :b (:c) .),
          output: [{
            '@id'   => "http://example.com/a",
            "http://example.com/b"  => [{
              "@list" => [
                {"@id" => "http://example.com/c"}
              ]
            }]
          }]
        },
        "empty list" => {
          input: %q(@prefix : <http://example.com/> . :a :b () .),
          output: [{
            '@id'   => "http://example.com/a",
            "http://example.com/b"  => [{"@list" => []}]
          }]
        },
        "single element list" => {
          input: %q(@prefix : <http://example.com/> . :a :b ( "apple" ) .),
          output: [{
            '@id'   => "http://example.com/a",
            "http://example.com/b"  => [{"@list" => [{"@value" => "apple"}]}]
          }]
        },
        "single element list without @type" => {
          input: %q(@prefix : <http://example.com/> . :a :b ( _:a ) . _:a :b "foo" .),
          output: [
            {
              '@id'   => "_:a",
              "http://example.com/b"  => [{"@value" => "foo"}]
            },
            {
              '@id'   => "http://example.com/a",
              "http://example.com/b"  => [{"@list" => [{"@id" => "_:a"}]}]
            },
          ]
        },
        "multiple graphs with shared BNode" => {
          input: %q(
            <http://www.example.com/z> <http://www.example.com/q> _:z0 <http://www.example.com/G> .
            _:z0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "cell-A" <http://www.example.com/G> .
            _:z0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:z1 <http://www.example.com/G> .
            _:z1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "cell-B" <http://www.example.com/G> .
            _:z1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://www.example.com/G> .
            <http://www.example.com/x> <http://www.example.com/p> _:z1 <http://www.example.com/G1> .
          ),
          output: [{
            "@id" => "http://www.example.com/G",
            "@graph" => [{
              "@id" => "_:z0",
              "http://www.w3.org/1999/02/22-rdf-syntax-ns#first" => [{"@value" => "cell-A"}],
              "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest" => [{"@id" => "_:z1"}]
            }, {
              "@id" => "_:z1",
              "http://www.w3.org/1999/02/22-rdf-syntax-ns#first" => [{"@value" => "cell-B"}],
              "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest" => [{"@list" => []}]
            }, {
              "@id" => "http://www.example.com/z",
              "http://www.example.com/q" => [{"@id" => "_:z0"}]
            }]
          },
          {
            "@id" => "http://www.example.com/G1",
            "@graph" => [{
              "@id" => "http://www.example.com/x",
              "http://www.example.com/p" => [{"@id" => "_:z1"}]
            }]
          }],
          reader: RDF::NQuads::Reader
        },
        "multiple graphs with shared BNode (at head)" => {
          input: %q(
            <http://www.example.com/z> <http://www.example.com/q> _:z0 <http://www.example.com/G> .
            _:z0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "cell-A" <http://www.example.com/G> .
            _:z0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:z1 <http://www.example.com/G> .
            _:z1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "cell-B" <http://www.example.com/G> .
            _:z1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://www.example.com/G> .
            <http://www.example.com/z> <http://www.example.com/q> _:z0 <http://www.example.com/G1> .
          ),
          output: [{
            "@id" => "http://www.example.com/G",
            "@graph" => [{
              "@id" => "_:z0",
              "http://www.w3.org/1999/02/22-rdf-syntax-ns#first" => [{"@value" => "cell-A"}],
              "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest" => [{"@list" => [{ "@value" => "cell-B" }]}]
            }, {
              "@id" => "http://www.example.com/z",
              "http://www.example.com/q" => [{"@id" => "_:z0"}]
            }]
          },
          {
            "@id" => "http://www.example.com/G1",
            "@graph" => [{
              "@id" => "http://www.example.com/z",
              "http://www.example.com/q" => [{"@id" => "_:z0"}]
            }]
          }],
          reader: RDF::NQuads::Reader
        },
        "@list containing empty @list" => {
          input: %(
            <http://example.com/a> <http://example.com/property> (()) .
          ),
          output: %([{
            "@id": "http://example.com/a",
            "http://example.com/property": [{"@list": [{"@list": []}]}]
          }]),
          reader: RDF::Turtle::Reader
        },
        "@list containing multiple lists" => {
          input: %(
            <http://example.com/a> <http://example.com/property> (("a") ("b")) .
          ),
          output: %([{
            "@id": "http://example.com/a",
            "http://example.com/property": [{"@list": [
              {"@list": [{"@value": "a"}]},
              {"@list": [{"@value": "b"}]}
            ]}]
          }]),
          reader: RDF::Turtle::Reader
        },
        "0008a" => {
          input: %(
          <http://example.com> <http://example.com/property> _:outerlist .
          _:outerlist <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> _:lista .
          _:outerlist <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:b0 .

          _:lista <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "a1" .
          _:lista <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:a2 .
          _:a2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "a2" .
          _:a2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:a3 .
          _:a3 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "a3" .
          _:a3 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .

          _:c0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> _:c1 .
          _:c0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          _:c1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "c1" .
          _:c1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:c2 .
          _:c2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "c2" .
          _:c2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:c3 .
          _:c3 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "c3" .
          _:c3 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .

          _:b0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> _:b1 .
          _:b0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:c0 .
          _:b1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "b1" .
          _:b1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:b2 .
          _:b2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "b2" .
          _:b2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:b3 .
          _:b3 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "b3" .
          _:b3 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          ),
          output: JSON.parse(%([
            {
              "@id": "http://example.com",
              "http://example.com/property": [
                {
                  "@list": [
                    {"@list": [{"@value": "a1"}, {"@value": "a2"}, {"@value": "a3"}]},
                    {"@list": [{"@value": "b1"}, {"@value": "b2"}, {"@value": "b3"}]},
                    {"@list": [{"@value": "c1"}, {"@value": "c2"}, {"@value": "c3"}]}
                  ]
                }
              ]
            }
          ])),
          reader: RDF::NQuads::Reader
        }
      }.each do |name, params|
        it "#{name}" do
          do_fromRdf(params)
        end
      end
    end
    
    context "quads" do
      {
        "simple named graph" => {
          input: %(
            <http://example.com/a> <http://example.com/b> <http://example.com/c> <http://example.com/U> .
          ),
          output: [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => [{"@id" => "http://example.com/c"}]
              }]
            },
          ]
        },
        "with properties" => {
          input: %(
            <http://example.com/a> <http://example.com/b> <http://example.com/c> <http://example.com/U> .
            <http://example.com/U> <http://example.com/d> <http://example.com/e> .
          ),
          output: [
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
          input: %(
            <http://example.com/a> <http://example.com/b> _:a <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/c> <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://example.com/U> .
            <http://example.com/U> <http://example.com/d> _:b .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/e> .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          ),
          output: [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => [{"@list" => [{"@id" => "http://example.com/c"}]}]
              }],
              "http://example.com/d" => [{"@list" => [{"@id" => "http://example.com/e"}]}]
            }
          ]
        },
        "Two Graphs with same subject and lists" => {
          input: %(
            <http://example.com/a> <http://example.com/b> _:a <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/c> <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://example.com/U> .
            <http://example.com/a> <http://example.com/b> _:b <http://example.com/V> .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/e> <http://example.com/V> .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://example.com/V> .
          ),
          output: [
            {
              "@id" => "http://example.com/U",
              "@graph" => [
                {
                  "@id" => "http://example.com/a",
                  "http://example.com/b" => [{
                    "@list" => [{"@id" => "http://example.com/c"}]
                  }]
                }
              ]
            },
            {
              "@id" => "http://example.com/V",
              "@graph" => [
                {
                  "@id" => "http://example.com/a",
                  "http://example.com/b" => [{
                    "@list" => [{"@id" => "http://example.com/e"}]
                  }]
                }
              ]
            }
          ]
        },
      }.each_pair do |name, params|
        it "#{name}" do
          do_fromRdf(params.merge(reader: RDF::NQuads::Reader))
        end
      end
    end
  
    context "problems" do
      {
        "xsd:boolean as value" => {
          input: %(
            @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
            @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

            <http://data.wikia.com/terms#playable> rdfs:range xsd:boolean .
          ),
          output: [{
            "@id" => "http://data.wikia.com/terms#playable",
            "http://www.w3.org/2000/01/rdf-schema#range" => [
              { "@id" => "http://www.w3.org/2001/XMLSchema#boolean" }
            ]
          }]
        },
      }.each do |t, params|
        it "#{t}" do
          do_fromRdf(params)
        end
      end
    end
  end

  def parse(input, **options)
    reader = options[:reader] || RDF::TriG::Reader
    reader.new(input, options, &:each_statement).to_a.extend(RDF::Enumerable)
  end

  # Serialize ntstr to a string and compare against regexps
  def serialize(ntstr, **options)
    logger.info ntstr if ntstr.is_a?(String)
    g = ntstr.is_a?(String) ? parse(ntstr, options) : ntstr
    logger.info g.dump(:trig)
    statements = g.each_statement.to_a
    JSON::LD::API.fromRdf(statements, logger: logger, **options)
  end

  def do_fromRdf(params)
    begin
      input, output, processingMode = params[:input], params[:output], params.fetch(:processingMode, 'json-ld-1.0')
      output = ::JSON.parse(output) if output.is_a?(String)
      jld = serialize(input, **params)
      expect(jld).to produce_jsonld(output, logger)
    rescue JSON::LD::JsonLdError => e
      fail("#{e.class}: #{e.message}\n" +
        "#{logger}\n" +
        "Backtrace:\n#{e.backtrace.join("\n")}")
    end
  end
end
