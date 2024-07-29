# frozen_string_literal: true

require_relative 'spec_helper'

describe JSON::LD::API do
  let(:logger) { RDF::Spec.logger }

  describe ".compact" do
    {
      "prefix" => {
        input: %({
          "@id": "http://example.com/a",
          "http://example.com/b": {"@id": "http://example.com/c"}
        }),
        context: %({"ex": "http://example.com/"}),
        output: %({
          "@context": {"ex": "http://example.com/"},
          "@id": "ex:a",
          "ex:b": {"@id": "ex:c"}
        })
      },
      "term" => {
        input: %({
          "@id": "http://example.com/a",
          "http://example.com/b": {"@id": "http://example.com/c"}
        }),
        context: %({"b": "http://example.com/b"}),
        output: %({
          "@context": {"b": "http://example.com/b"},
          "@id": "http://example.com/a",
          "b": {"@id": "http://example.com/c"}
        })
      },
      "integer value" => {
        input: %({
          "@id": "http://example.com/a",
          "http://example.com/b": {"@value": 1}
        }),
        context: %({"b": "http://example.com/b"}),
        output: %({
          "@context": {"b": "http://example.com/b"},
          "@id": "http://example.com/a",
          "b": 1
        })
      },
      "boolean value" => {
        input: %({
          "@id": "http://example.com/a",
          "http://example.com/b": {"@value": true}
        }),
        context: %({"b": "http://example.com/b"}),
        output: %({
          "@context": {"b": "http://example.com/b"},
          "@id": "http://example.com/a",
          "b": true
        })
      },
      "@id" => {
        input: %({"@id": "http://example.org/test#example"}),
        context: {},
        output: {}
      },
      "@id coercion" => {
        input: %({
          "@id": "http://example.com/a",
          "http://example.com/b": {"@id": "http://example.com/c"}
        }),
        context: %({"b": {"@id": "http://example.com/b", "@type": "@id"}}),
        output: %({
          "@context": {"b": {"@id": "http://example.com/b", "@type": "@id"}},
          "@id": "http://example.com/a",
          "b": "http://example.com/c"
        })
      },
      "xsd:date coercion" => {
        input: %({
          "http://example.com/b": {"@value": "2012-01-04", "@type": "http://www.w3.org/2001/XMLSchema#date"}
        }),
        context: %({
          "xsd": "http://www.w3.org/2001/XMLSchema#",
          "b": {"@id": "http://example.com/b", "@type": "xsd:date"}
        }),
        output: %({
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "b": {"@id": "http://example.com/b", "@type": "xsd:date"}
          },
          "b": "2012-01-04"
        })
      },
      '@list coercion': {
        input: %({
          "http://example.com/b": {"@list": ["c", "d"]}
        }),
        context: %({"b": {"@id": "http://example.com/b", "@container": "@list"}}),
        output: %({
          "@context": {"b": {"@id": "http://example.com/b", "@container": "@list"}},
          "b": ["c", "d"]
        })
      },
      "@list coercion (integer)" => {
        input: %({
          "http://example.com/term": [
            {"@list": [1]}
          ]
        }),
        context: %({
          "term4": {"@id": "http://example.com/term", "@container": "@list"},
          "@language": "de"
        }),
        output: %({
          "@context": {
            "term4": {"@id": "http://example.com/term", "@container": "@list"},
            "@language": "de"
          },
          "term4": [1]
        })
      },
      "@set coercion" => {
        input: %({
          "http://example.com/b": {"@set": ["c"]}
        }),
        context: %({"b": {"@id": "http://example.com/b", "@container": "@set"}}),
        output: %({
          "@context": {"b": {"@id": "http://example.com/b", "@container": "@set"}},
          "b": ["c"]
        })
      },
      "@set coercion on @type" => {
        input: %({
          "@type": "http://www.w3.org/2000/01/rdf-schema#Resource",
          "http://example.org/foo": {"@value": "bar", "@type": "http://example.com/type"}
        }),
        context: %({"@version": 1.1, "@type": {"@container": "@set"}}),
        output: %({
          "@context": {"@version": 1.1, "@type": {"@container": "@set"}},
          "@type": ["http://www.w3.org/2000/01/rdf-schema#Resource"],
          "http://example.org/foo": {"@value": "bar", "@type": "http://example.com/type"}
        })
      },
      "empty @set coercion" => {
        input: %({
          "http://example.com/b": []
        }),
        context: %({"b": {"@id": "http://example.com/b", "@container": "@set"}}),
        output: %({
          "@context": {"b": {"@id": "http://example.com/b", "@container": "@set"}},
          "b": []
        })
      },
      "@type with string @id" => {
        input: %({
          "@id": "http://example.com/",
          "@type": "#{RDF::RDFS.Resource}"
        }),
        context: {},
        output: %({
          "@id": "http://example.com/",
          "@type": "#{RDF::RDFS.Resource}"
        })
      },
      "@type with array @id" => {
        input: %({
          "@id": "http://example.com/",
          "@type": ["#{RDF::RDFS.Resource}"]
        }),
        context: {},
        output: %({
          "@id": "http://example.com/",
          "@type": "#{RDF::RDFS.Resource}"
        })
      },
      "default language" => {
        input: %({
          "http://example.com/term": [
            "v5",
            {"@value": "plain literal"}
          ]
        }),
        context: %({
          "term5": {"@id": "http://example.com/term", "@language": null},
          "@language": "de"
        }),
        output: %({
          "@context": {
            "term5": {"@id": "http://example.com/term", "@language": null},
            "@language": "de"
          },
          "term5": [ "v5", "plain literal" ]
        })
      },
      "default direction" => {
        input: %({
          "http://example.com/term": [
            "v5",
            {"@value": "plain literal"}
          ]
        }),
        context: %({
          "term5": {"@id": "http://example.com/term", "@direction": null},
          "@direction": "ltr"
        }),
        output: %({
          "@context": {
            "term5": {"@id": "http://example.com/term", "@direction": null},
            "@direction": "ltr"
          },
          "term5": [ "v5", "plain literal" ]
        })
      }
    }.each_pair do |title, params|
      it(title) { run_compact(params) }
    end

    context "keyword aliasing" do
      {
        "@id" => {
          input: %({
            "@id": "",
            "@type": "#{RDF::RDFS.Resource}"
          }),
          context: %({"id": "@id"}),
          output: %({
            "@context": {"id": "@id"},
            "id": "",
            "@type": "#{RDF::RDFS.Resource}"
          })
        },
        '@type': {
          input: %({
            "@type": "http://www.w3.org/2000/01/rdf-schema#Resource",
            "http://example.org/foo": {"@value": "bar", "@type": "http://example.com/type"}
          }),
          context: %({"type": "@type"}),
          output: %({
            "@context": {"type": "@type"},
            "type": "http://www.w3.org/2000/01/rdf-schema#Resource",
            "http://example.org/foo": {"@value": "bar", "type": "http://example.com/type"}
          })
        },
        '@type with @container: @set': {
          input: %({
            "@type": "http://www.w3.org/2000/01/rdf-schema#Resource",
            "http://example.org/foo": {"@value": "bar", "@type": "http://example.com/type"}
          }),
          context: %({"type": {"@id": "@type", "@container": "@set"}}),
          output: %({
            "@context": {"type": {"@id": "@type", "@container": "@set"}},
            "type": ["http://www.w3.org/2000/01/rdf-schema#Resource"],
            "http://example.org/foo": {"@value": "bar", "type": "http://example.com/type"}
          }),
          processingMode: 'json-ld-1.1'
        },
        "@language" => {
          input: %({
            "http://example.org/foo": {"@value": "bar", "@language": "baz"}
          }),
          context: %({"language": "@language"}),
          output: %({
            "@context": {"language": "@language"},
            "http://example.org/foo": {"@value": "bar", "language": "baz"}
          })
        },
        "@direction" => {
          input: %({
            "http://example.org/foo": {"@value": "bar", "@direction": "ltr"}
          }),
          context: %({"direction": "@direction"}),
          output: %({
            "@context": {"direction": "@direction"},
            "http://example.org/foo": {"@value": "bar", "direction": "ltr"}
          })
        },
        "@value" => {
          input: %({
            "http://example.org/foo": {"@value": "bar", "@language": "baz"}
          }),
          context: %({"literal": "@value"}),
          output: %({
            "@context": {"literal": "@value"},
            "http://example.org/foo": {"literal": "bar", "@language": "baz"}
          })
        },
        "@list" => {
          input: %({
            "http://example.org/foo": {"@list": ["bar"]}
          }),
          context: %({"list": "@list"}),
          output: %({
            "@context": {"list": "@list"},
            "http://example.org/foo": {"list": ["bar"]}
          })
        }
      }.each do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "term selection" do
      {
        "Uses term with null language when two terms conflict on language" => {
          input: %([{
            "http://example.com/term": {"@value": "v1"}
          }]),
          context: %({
            "term5": {"@id": "http://example.com/term","@language": null},
            "@language": "de"
          }),
          output: %({
            "@context": {
              "term5": {"@id": "http://example.com/term","@language": null},
              "@language": "de"
            },
            "term5": "v1"
          })
        },
        "Uses term with null direction when two terms conflict on direction" => {
          input: %([{
            "http://example.com/term": {"@value": "v1"}
          }]),
          context: %({
            "term5": {"@id": "http://example.com/term","@direction": null},
            "@direction": "ltr"
          }),
          output: %({
            "@context": {
              "term5": {"@id": "http://example.com/term","@direction": null},
              "@direction": "ltr"
            },
            "term5": "v1"
          })
        },
        "Uses subject alias" => {
          input: %([{
            "@id": "http://example.com/id1",
            "http://example.com/id1": {"@value": "foo", "@language": "de"}
          }]),
          context: %({
            "id1": "http://example.com/id1",
            "@language": "de"
          }),
          output: %({
            "@context": {
              "id1": "http://example.com/id1",
              "@language": "de"
            },
            "@id": "http://example.com/id1",
            "id1": "foo"
          })
        },
        "compact-0007" => {
          input: %(
            {"http://example.org/vocab#contains": "this-is-not-an-IRI"}
          ),
          context: %({
            "ex": "http://example.org/vocab#",
            "ex:contains": {"@type": "@id"}
          }),
          output: %({
            "@context": {
              "ex": "http://example.org/vocab#",
              "ex:contains": {"@type": "@id"}
            },
            "http://example.org/vocab#contains": "this-is-not-an-IRI"
          })
        },
        "Language map term with language value" => {
          input: %([{"http://example/t": {"@value": "foo", "@language": "en"}}]),
          context: %({"t": {"@id": "http://example/t", "@container": "@language"}}),
          output: %({
            "@context": {
              "t": {"@id": "http://example/t", "@container": "@language"}
            },
            "t": {"en": "foo"}
          })
        },
        "Datatyped term with datatyped value" => {
          input: %([{"http://example/t": {"@value": "foo", "@type": "http:/example/type"}}]),
          context: %({"t": {"@id": "http://example/t", "@type": "http:/example/type"}}),
          output: %({
            "@context": {
              "t": {"@id": "http://example/t", "@type": "http:/example/type"}
            },
            "t": "foo"
          })
        },
        "Datatyped term with simple value" => {
          input: %([{"http://example/t": {"@value": "foo"}}]),
          context: %({"t": {"@id": "http://example/t", "@type": "http:/example/type"}}),
          output: %({
            "@context": {
              "t": {"@id": "http://example/t", "@type": "http:/example/type"}
            },
            "http://example/t": "foo"
          })
        },
        "Datatyped term with object value" => {
          input: %([{"http://example/t": {"@id": "http://example/id"}}]),
          context: %({"t": {"@id": "http://example/t", "@type": "http:/example/type"}}),
          output: %({
            "@context": {
              "t": {"@id": "http://example/t", "@type": "http:/example/type"}
            },
            "http://example/t": {"@id": "http://example/id"}
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "IRI Compaction" do
      {
        "Expands and compacts to document base in 1.0" => {
          input: %({
            "@id": "a",
            "http://example.com/b": {"@id": "c"}
          }),
          context: %({"b": "http://example.com/b"}),
          output: %({
            "@context": {"b": "http://example.com/b"},
            "@id": "a",
            "b": {"@id": "c"}
          }),
          base: "http://example.org/"
        },
        "Expands and compacts to document base in 1.1 with compactToRelative true" => {
          input: %({
            "@id": "a",
            "http://example.com/b": {"@id": "c"}
          }),
          context: %({"b": "http://example.com/b"}),
          output: %({
            "@context": {"b": "http://example.com/b"},
            "@id": "a",
            "b": {"@id": "c"}
          }),
          base: "http://example.org/",
          compactToRelative: true,
          processingMode: 'json-ld-1.1'
        },
        "Expands but does not compact to document base in 1.1 with compactToRelative false" => {
          input: %({
            "@id": "http://example.org/a",
            "http://example.com/b": {"@id": "http://example.org/c"}
          }),
          context: %({"b": "http://example.com/b"}),
          output: %({
            "@context": {"b": "http://example.com/b"},
            "@id": "http://example.org/a",
            "b": {"@id": "http://example.org/c"}
          }),
          compactToRelative: false,
          processingMode: 'json-ld-1.1'
        },
        "Expands and compacts to document base in 1.1 by default" => {
          input: %({
            "@id": "a",
            "http://example.com/b": {"@id": "c"}
          }),
          context: %({"b": "http://example.com/b"}),
          output: %({
            "@context": {"b": "http://example.com/b"},
            "@id": "a",
            "b": {"@id": "c"}
          }),
          base: "http://example.org/",
          processingMode: 'json-ld-1.1'
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "@container: @reverse" do
      {
        "@container: @reverse" => {
          input: %([{
            "@id": "http://example/one",
            "@reverse": {
              "http://example/forward": [
                {
                  "@id": "http://example/two"
                }
              ]
            }
          }]),
          context: %({
            "@vocab": "http://example/",
            "rev": { "@reverse": "forward", "@type": "@id"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "rev": { "@reverse": "forward", "@type": "@id"}
            },
            "@id": "http://example/one",
            "rev": "http://example/two"
          })
        },
        "compact-0033" => {
          input: %([
            {
              "@id": "http://example.com/people/markus",
              "@reverse": {
                "http://xmlns.com/foaf/0.1/knows": [
                  {
                    "@id": "http://example.com/people/dave",
                    "http://xmlns.com/foaf/0.1/name": [ { "@value": "Dave Longley" } ]
                  }
                ]
              },
              "http://xmlns.com/foaf/0.1/name": [ { "@value": "Markus Lanthaler" } ]
            }
          ]),
          context: %({
            "name": "http://xmlns.com/foaf/0.1/name",
            "isKnownBy": { "@reverse": "http://xmlns.com/foaf/0.1/knows" }
          }),
          output: %({
            "@context": {
              "name": "http://xmlns.com/foaf/0.1/name",
              "isKnownBy": {
                "@reverse": "http://xmlns.com/foaf/0.1/knows"
              }
            },
            "@id": "http://example.com/people/markus",
            "name": "Markus Lanthaler",
            "isKnownBy": {
              "@id": "http://example.com/people/dave",
              "name": "Dave Longley"
            }
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "context as value" do
      {
        "includes the context in the output document" => {
          input: %({
            "http://example.com/": "bar"
          }),
          context: %({
            "foo": "http://example.com/"
          }),
          output: %({
            "@context": {
              "foo": "http://example.com/"
            },
            "foo": "bar"
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "context as reference" do
      let(:remote_doc) do
        JSON::LD::API::RemoteDocument.new(
          '{"@context": {"b": "http://example.com/b"}}',
          documentUrl: "http://example.com/context"
        )
      end

      it "uses referenced context" do
        JSON::LD::Context.instance_variable_set(:@cache, nil)
        input = JSON.parse %({
          "http://example.com/b": "c"
        })
        expected = JSON.parse %({
          "@context": "http://example.com/context",
          "b": "c"
        })
        allow(described_class).to receive(:documentLoader).with("http://example.com/context",
          anything).and_yield(remote_doc)
        jld = described_class.compact(input, "http://example.com/context", logger: logger, validate: true)
        expect(jld).to produce_jsonld(expected, logger)
      end
    end

    context "@list" do
      {
        "1 term 2 lists 2 languages" => {
          input: %([{
            "http://example.com/foo": [
              {"@list": [{"@value": "en", "@language": "en"}]},
              {"@list": [{"@value": "de", "@language": "de"}]}
            ]
          }]),
          context: %({
            "foo_en": {"@id": "http://example.com/foo", "@container": "@list", "@language": "en"},
            "foo_de": {"@id": "http://example.com/foo", "@container": "@list", "@language": "de"}
          }),
          output: %({
            "@context": {
              "foo_en": {"@id": "http://example.com/foo", "@container": "@list", "@language": "en"},
              "foo_de": {"@id": "http://example.com/foo", "@container": "@list", "@language": "de"}
            },
            "foo_en": ["en"],
            "foo_de": ["de"]
          })
        },
        "1 term 2 lists 2 directions" => {
          input: %([{
            "http://example.com/foo": [
              {"@list": [{"@value": "en", "@direction": "ltr"}]},
              {"@list": [{"@value": "ar", "@direction": "rtl"}]}
            ]
          }]),
          context: %({
            "foo_ltr": {"@id": "http://example.com/foo", "@container": "@list", "@direction": "ltr"},
            "foo_rtl": {"@id": "http://example.com/foo", "@container": "@list", "@direction": "rtl"}
          }),
          output: %({
            "@context": {
              "foo_ltr": {"@id": "http://example.com/foo", "@container": "@list", "@direction": "ltr"},
              "foo_rtl": {"@id": "http://example.com/foo", "@container": "@list", "@direction": "rtl"}
            },
            "foo_ltr": ["en"],
            "foo_rtl": ["ar"]
          })
        },
        "coerced @list containing an empty list" => {
          input: %([{
            "http://example.com/foo": [{"@list": [{"@list": []}]}]
          }]),
          context: %({
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          }),
          output: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [[]]
          })
        },
        "coerced @list containing a list" => {
          input: %([{
            "http://example.com/foo": [{"@list": [{"@list": [{"@value": "baz"}]}]}]
          }]),
          context: %({
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          }),
          output: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [["baz"]]
          })
        },
        "coerced @list containing an deep list" => {
          input: %([{
            "http://example.com/foo": [{"@list": [{"@list": [{"@list": [{"@value": "baz"}]}]}]}]
          }]),
          context: %({
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          }),
          output: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [[["baz"]]]
          })
        },
        "coerced @list containing multiple lists" => {
          input: %([{
            "http://example.com/foo": [{"@list": [
              {"@list": [{"@value": "a"}]},
              {"@list": [{"@value": "b"}]}
            ]}]
          }]),
          context: %({
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          }),
          output: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [["a"], ["b"]]
          })
        },
        "coerced @list containing mixed list values" => {
          input: %([{
            "http://example.com/foo": [{"@list": [
              {"@list": [{"@value": "a"}]},
              {"@value": "b"}
            ]}]
          }]),
          context: %({
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          }),
          output: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [["a"], "b"]
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "with @type: @json" do
      {
        true => {
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#bool", "@type": "@json"}
            },
            "e": true
          }),
          input: %( [{
            "http://example.org/vocab#bool": [{"@value": true, "@type": "@json"}]
          }])
        },
        false => {
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#bool", "@type": "@json"}
            },
            "e": false
          }),
          input: %([{
            "http://example.org/vocab#bool": [{"@value": false, "@type": "@json"}]
          }])
        },
        double: {
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#double", "@type": "@json"}
            },
            "e": 1.23
          }),
          input: %([{
            "http://example.org/vocab#double": [{"@value": 1.23, "@type": "@json"}]
          }])
        },
        'double-zero': {
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#double", "@type": "@json"}
            },
            "e": 0.0e0
          }),
          input: %([{
            "http://example.org/vocab#double": [{"@value": 0.0e0, "@type": "@json"}]
          }])
        },
        integer: {
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#integer", "@type": "@json"}
            },
            "e": 123
          }),
          input: %([{
            "http://example.org/vocab#integer": [{"@value": 123, "@type": "@json"}]
          }])
        },
        string: {
          input: %([{
            "http://example.org/vocab#string": [{
              "@value": "string",
              "@type": "@json"
            }]
          }]),
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#string", "@type": "@json"}
            },
            "e": "string"
          })
        },
        null: {
          input: %([{
            "http://example.org/vocab#null": [{
              "@value": null,
              "@type": "@json"
            }]
          }]),
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#null", "@type": "@json"}
            },
            "e": null
          })
        },
        object: {
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#object", "@type": "@json"}
            },
            "e": {"foo": "bar"}
          }),
          input: %([{
            "http://example.org/vocab#object": [{"@value": {"foo": "bar"}, "@type": "@json"}]
          }])
        },
        array: {
          output: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#array", "@type": "@json", "@container": "@set"}
            },
            "e": [{"foo": "bar"}]
          }),
          input: %([{
            "http://example.org/vocab#array": [{"@value": [{"foo": "bar"}], "@type": "@json"}]
          }])
        },
        'Already expanded object': {
          output: %({
            "@context": {"@version": 1.1},
            "http://example.org/vocab#object": {"@value": {"foo": "bar"}, "@type": "@json"}
          }),
          input: %([{
            "http://example.org/vocab#object": [{"@value": {"foo": "bar"}, "@type": "@json"}]
          }])
        },
        'Already expanded object with aliased keys': {
          output: %({
            "@context": {"@version": 1.1, "value": "@value", "type": "@type", "json": "@json"},
            "http://example.org/vocab#object": {"value": {"foo": "bar"}, "type": "json"}
          }),
          input: %([{
            "http://example.org/vocab#object": [{"@value": {"foo": "bar"}, "@type": "@json"}]
          }])
        }
      }.each do |title, params|
        it(title) { run_compact(processingMode: 'json-ld-1.1', **params) }
      end
    end

    context "@container: @index" do
      {
        "compact-0029" => {
          input: %([{
             "@id": "http://example.com/article",
             "http://example.com/vocab/author": [{
                "@id": "http://example.org/person/1",
                "@index": "regular"
             }, {
                "@id": "http://example.org/guest/cd24f329aa",
                "@index": "guest"
             }]
          }]),
          context: %({
            "author": {"@id": "http://example.com/vocab/author", "@container": "@index" }
          }),
          output: %({
            "@context": {
              "author": {
                "@id": "http://example.com/vocab/author",
                "@container": "@index"
              }
            },
            "@id": "http://example.com/article",
            "author": {
              "regular": {
                "@id": "http://example.org/person/1"
              },
              "guest": {
                "@id": "http://example.org/guest/cd24f329aa"
              }
            }
          })
        },
        "simple map with @none node definition" => {
          input: %([{
             "@id": "http://example.com/article",
             "http://example.com/vocab/author": [{
                "@id": "http://example.org/person/1",
                "@index": "regular"
             }, {
                "@id": "http://example.org/guest/cd24f329aa"
             }]
          }]),
          context: %({
            "author": {"@id": "http://example.com/vocab/author", "@container": "@index" }
          }),
          output: %({
            "@context": {
              "author": {
                "@id": "http://example.com/vocab/author",
                "@container": "@index"
              }
            },
            "@id": "http://example.com/article",
            "author": {
              "regular": {
                "@id": "http://example.org/person/1"
              },
              "@none": {
                "@id": "http://example.org/guest/cd24f329aa"
              }
            }
          }),
          processingMode: 'json-ld-1.1'
        },
        "simple map with @none value" => {
          input: %([{
             "@id": "http://example.com/article",
             "http://example.com/vocab/author": [{
                "@value": "Gregg",
                "@index": "regular"
             }, {
                "@value": "Manu"
             }]
          }]),
          context: %({
            "author": {"@id": "http://example.com/vocab/author", "@container": "@index" }
          }),
          output: %({
            "@context": {
              "author": {
                "@id": "http://example.com/vocab/author",
                "@container": "@index"
              }
            },
            "@id": "http://example.com/article",
            "author": {
              "regular": "Gregg",
              "@none": "Manu"
            }
          }),
          processingMode: 'json-ld-1.1'
        },
        "simple map with @none value using alias of @none" => {
          input: %([{
             "@id": "http://example.com/article",
             "http://example.com/vocab/author": [{
                "@value": "Gregg",
                "@index": "regular"
             }, {
                "@value": "Manu"
             }]
          }]),
          context: %({
            "author": {"@id": "http://example.com/vocab/author", "@container": "@index" },
            "none": "@none"
          }),
          output: %({
            "@context": {
              "author": {
                "@id": "http://example.com/vocab/author",
                "@container": "@index"
              },
              "none": "@none"
            },
            "@id": "http://example.com/article",
            "author": {
              "regular": "Gregg",
              "none": "Manu"
            }
          }),
          processingMode: 'json-ld-1.1'
        },
        'issue-514': {
          input: %({
            "http://example.org/ns/prop": [{
              "@id": "http://example.org/ns/bar",
              "http://example.org/ns/name": "bar"
            }, {
                "@id": "http://example.org/ns/foo",
              "http://example.org/ns/name": "foo"
            }]
          }),
          context: %({
            "@context": {
              "ex": "http://example.org/ns/",
              "prop": {
                "@id": "ex:prop",
                "@container": "@index",
                "@index": "ex:name"
              }
            }
          }),
          output: %({
            "@context": {
              "ex": "http://example.org/ns/",
              "prop": {
                "@id": "ex:prop",
                "@container": "@index",
                "@index": "ex:name"
              }
            },
            "prop": {
              "foo": { "@id": "ex:foo"},
              "bar": { "@id": "ex:bar"}
            }
          })
        },
        'issue-514b': {
          input: %({
            "http://example.org/ns/prop": [{
              "@id": "http://example.org/ns/bar",
              "http://example.org/ns/name": "bar"
            }, {
                "@id": "http://example.org/ns/foo",
              "http://example.org/ns/name": "foo"
            }]
          }),
          context: %({
            "@context": {
              "ex": "http://example.org/ns/",
              "prop": {
                "@id": "ex:prop",
                "@container": "@index",
                "@index": "http://example.org/ns/name"
              }
            }
          }),
          output: %({
            "@context": {
              "ex": "http://example.org/ns/",
              "prop": {
                "@id": "ex:prop",
                "@container": "@index",
                "@index": "http://example.org/ns/name"
              }
            },
            "prop": {
              "foo": { "@id": "ex:foo"},
              "bar": { "@id": "ex:bar"}
            }
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end

      context "@index: property" do
        {
          'property-valued index indexes property value, instead of property (value)': {
            output: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"}
              },
              "@id": "article",
              "author": {
                "regular": {"@id": "person/1"},
                "guest": [{"@id": "person/2"}, {"@id": "person/3"}]
              }
            }),
            input: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@value": "regular"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@value": "guest"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@value": "guest"}]}
              ]
            }])
          },
          'property-valued index indexes property value, instead of @index (multiple values)': {
            output: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"}
              },
              "@id": "article",
              "author": {
                "regular": {"@id": "person/1", "prop": "foo"},
                "guest": [
                  {"@id": "person/2", "prop": "foo"},
                  {"@id": "person/3", "prop": "foo"}
                ]
              }
            }),
            input: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@value": "regular"}, {"@value": "foo"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@value": "guest"}, {"@value": "foo"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@value": "guest"}, {"@value": "foo"}]}
              ]
            }])
          },
          'property-valued index extracts property value, instead of @index (node)': {
            output: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@vocab", "@container": "@index", "@index": "prop"},
                "prop": {"@type": "@id"}
              },
              "@id": "article",
              "author": {
                "regular": {"@id": "person/1"},
                "guest": [
                  {"@id": "person/2"},
                  {"@id": "person/3"}
                ]
              }
            }),
            input: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@id": "http://example.com/regular"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@id": "http://example.com/guest"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@id": "http://example.com/guest"}]}
              ]
            }])
          },
          'property-valued index indexes property value, instead of property (multimple nodes)': {
            output: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@vocab", "@container": "@index", "@index": "prop"},
                "prop": {"@type": "@id"}
              },
              "@id": "article",
              "author": {
                "regular": {"@id": "person/1", "prop": "foo"},
                "guest": [
                  {"@id": "person/2", "prop": "foo"},
                  {"@id": "person/3", "prop": "foo"}
                ]
              }
            }),
            input: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@id": "http://example.com/regular"}, {"@id": "http://example.com/foo"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@id": "http://example.com/guest"}, {"@id": "http://example.com/foo"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@id": "http://example.com/guest"}, {"@id": "http://example.com/foo"}]}
              ]
            }])
          },
          'property-valued index indexes using @none if no property value exists': {
            output: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"}
              },
              "@id": "article",
              "author": {
                "@none": ["person/1", "person/2", "person/3"]
              }
            }),
            input: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1"},
                {"@id": "http://example.com/person/2"},
                {"@id": "http://example.com/person/3"}
              ]
            }])
          },
          'property-valued index indexes using @none if no property value does not compact to string': {
            output: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"}
              },
              "@id": "article",
              "author": {
                "@none": [
                  {"@id": "person/1", "prop": {"@id": "regular"}},
                  {"@id": "person/2", "prop": {"@id": "guest"}},
                  {"@id": "person/3", "prop": {"@id": "guest"}}
                ]
              }
            }),
            input: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@id": "http://example.com/regular"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@id": "http://example.com/guest"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@id": "http://example.com/guest"}]}
              ]
            }])
          }
        }.each do |title, params|
          it(title) { run_compact(**params) }
        end
      end
    end

    context "@container: @language" do
      {
        "compact-0024" => {
          input: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "The Queen", "@language": "en"},
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de"}
              ]
            }
          ]),
          context: %({
            "vocab": "http://example.com/vocab/",
            "label": {"@id": "vocab:label", "@container": "@language"}
          }),
          output: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "label": {"@id": "vocab:label", "@container": "@language"}
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": ["Die Königin", "Ihre Majestät"]
            }
          })
        },
        "with no @language" => {
          input: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "The Queen", "@language": "en"},
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät"}
              ]
            }
          ]),
          context: %({
            "vocab": "http://example.com/vocab/",
            "label": {"@id": "vocab:label", "@container": "@language"}
          }),
          output: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "label": {"@id": "vocab:label", "@container": "@language"}
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": "Die Königin",
              "@none": "Ihre Majestät"
            }
          }),
          processingMode: "json-ld-1.1"
        },
        "with no @language using alias of @none" => {
          input: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "The Queen", "@language": "en"},
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät"}
              ]
            }
          ]),
          context: %({
            "vocab": "http://example.com/vocab/",
            "label": {"@id": "vocab:label", "@container": "@language"},
            "none": "@none"
          }),
          output: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "label": {"@id": "vocab:label", "@container": "@language"},
              "none": "@none"
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": "Die Königin",
              "none": "Ihre Majestät"
            }
          }),
          processingMode: "json-ld-1.1"
        },
        'simple map with term direction': {
          input: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de", "@direction": "ltr"},
                {"@value": "Ihre Majestät", "@language": "de", "@direction": "ltr"},
                {"@value": "The Queen", "@language": "en", "@direction": "ltr"}
              ]
            }
          ]),
          context: %({
            "@context": {
              "@version": 1.1,
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": "ltr",
                "@container": "@language"
              }
            }
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": "ltr",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          processingMode: "json-ld-1.1"
        },
        'simple map with overriding term direction': {
          input: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de", "@direction": "ltr"},
                {"@value": "Ihre Majestät", "@language": "de", "@direction": "ltr"},
                {"@value": "The Queen", "@language": "en", "@direction": "ltr"}
              ]
            }
          ]),
          context: %({
            "@context": {
              "@version": 1.1,
              "@direction": "rtl",
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": "ltr",
                "@container": "@language"
              }
            }
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "@direction": "rtl",
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": "ltr",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          processingMode: "json-ld-1.1"
        },
        'simple map with overriding null direction': {
          input: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de"},
                {"@value": "The Queen", "@language": "en"}
              ]
            }
          ]),
          context: %({
            "@context": {
              "@version": 1.1,
              "@direction": "rtl",
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": null,
                "@container": "@language"
              }
            }
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "@direction": "rtl",
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": null,
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          processingMode: "json-ld-1.1"
        },
        'simple map with mismatching term direction': {
          input: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de", "@direction": "ltr"},
                {"@value": "The Queen", "@language": "en", "@direction": "rtl"}
              ]
            }
          ]),
          context: %({
            "@context": {
              "@version": 1.1,
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": "rtl",
                "@container": "@language"
              }
            }
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": "rtl",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen"
            },
            "vocab:label": [
              {"@value": "Die Königin", "@language": "de"},
              {"@value": "Ihre Majestät", "@language": "de", "@direction": "ltr"}
            ]
          }),
          processingMode: "json-ld-1.1"
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "@container: @id" do
      {
        "Indexes to object not having an @id" => {
          input: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with @id _:bar"}], "@id": "_:bar"},
              {"http://example/label": [{"@value": "Object with @id <foo>"}], "@id": "http://example.org/foo"}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "idmap": {"@container": "@id"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "http://example.org/foo": {"label": "Object with @id <foo>"},
              "_:bar": {"label": "Object with @id _:bar"}
            }
          })
        },
        "Indexes to object already having an @id" => {
          input: %([{
            "http://example/idmap": [
              {"@id": "_:foo", "http://example/label": [{"@value": "Object with @id _:bar"}]},
              {"@id": "http://example.org/bar", "http://example/label": [{"@value": "Object with @id <foo>"}]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "idmap": {"@container": "@id"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "_:foo": {"label": "Object with @id _:bar"},
              "http://example.org/bar": {"label": "Object with @id <foo>"}
            }
          })
        },
        "Indexes to object using compact IRI @id" => {
          input: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with @id <foo>"}], "@id": "http://example.org/foo"}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "ex": "http://example.org/",
            "idmap": {"@container": "@id"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "ex": "http://example.org/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "ex:foo": {"label": "Object with @id <foo>"}
            }
          })
        },
        "Indexes using @none" => {
          input: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with no @id"}]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "ex": "http://example.org/",
            "idmap": {"@container": "@id"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "ex": "http://example.org/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "@none": {"label": "Object with no @id"}
            }
          })
        },
        "Indexes using @none with alias" => {
          input: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with no @id"}]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "ex": "http://example.org/",
            "idmap": {"@container": "@id"},
            "none": "@none"
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "ex": "http://example.org/",
              "idmap": {"@container": "@id"},
              "none": "@none"
            },
            "idmap": {
              "none": {"label": "Object with no @id"}
            }
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "@container: @type" do
      {
        "Indexes to object not having an @type" => {
          input: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type _:bar"}], "@type": ["_:bar"]},
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example.org/foo"]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "typemap": {"@container": "@type"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"label": "Object with @type <foo>"},
              "_:bar": {"label": "Object with @type _:bar"}
            }
          })
        },
        "Indexes to object already having an @type" => {
          input: %([{
            "http://example/typemap": [
              {
                "@type": ["_:bar", "_:foo"],
                "http://example/label": [{"@value": "Object with @type _:bar"}]
              },
              {
                "@type": ["http://example.org/foo", "http://example.org/bar"],
                "http://example/label": [{"@value": "Object with @type <foo>"}]
              }
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "typemap": {"@container": "@type"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"@type": "http://example.org/bar", "label": "Object with @type <foo>"},
              "_:bar": {"@type": "_:foo", "label": "Object with @type _:bar"}
            }
          })
        },
        "Indexes to object already having multiple @type values" => {
          input: %([{
            "http://example/typemap": [
              {
                "@type": ["_:bar", "_:foo", "_:baz"],
                "http://example/label": [{"@value": "Object with @type _:bar"}]
              },
              {
                "@type": ["http://example.org/foo", "http://example.org/bar", "http://example.org/baz"],
                "http://example/label": [{"@value": "Object with @type <foo>"}]
              }
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "typemap": {"@container": "@type"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"@type": ["http://example.org/bar", "http://example.org/baz"], "label": "Object with @type <foo>"},
              "_:bar": {"@type": ["_:foo", "_:baz"], "label": "Object with @type _:bar"}
            }
          })
        },
        "Indexes using compacted @type" => {
          input: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example/Foo"]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "typemap": {"@container": "@type"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "Foo": {"label": "Object with @type <foo>"}
            }
          })
        },
        "Indexes using @none" => {
          input: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with no @type"}]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "ex": "http://example.org/",
            "typemap": {"@container": "@type"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "ex": "http://example.org/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "@none": {"label": "Object with no @type"}
            }
          })
        },
        "Indexes using @none with alias" => {
          input: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with no @id"}]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "ex": "http://example.org/",
            "typemap": {"@container": "@type"},
            "none": "@none"
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "ex": "http://example.org/",
              "typemap": {"@container": "@type"},
              "none": "@none"
            },
            "typemap": {
              "none": {"label": "Object with no @id"}
            }
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "@container: @graph" do
      {
        "Compacts simple graph" => {
          input: %([{
            "http://example.org/input": [{
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }]
            }]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "input": {"@container": "@graph"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": "@graph"}
            },
            "input": {
              "value": "x"
            }
          })
        },
        "Compacts simple graph with @set" => {
          input: %([{
            "http://example.org/input": [{
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }]
            }]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "input": {"@container": ["@graph", "@set"]}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@set"]}
            },
            "input": [{
              "value": "x"
            }]
          })
        },
        "Compacts simple graph with @index" => {
          input: %([{
            "http://example.org/input": [{
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }],
              "@index": "ndx"
            }]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "input": {"@container": "@graph"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": "@graph"}
            },
            "input": {
              "value": "x"
            }
          })
        },
        "Compacts simple graph with @index and multiple nodes" => {
          input: %([{
            "http://example.org/input": [{
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }, {
                "http://example.org/value": [{"@value": "y"}]
              }],
              "@index": "ndx"
            }]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "input": {"@container": "@graph"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": "@graph"}
            },
            "input": {
              "@included": [{
                "value": "x"
              }, {
                "value": "y"
              }]
            }
          })
        },
        "Does not compact graph with @id" => {
          input: %([{
            "http://example.org/input": [{
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }],
              "@id": "http://example.org/id"
            }]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "input": {"@container": "@graph"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": "@graph"}
            },
            "input": {
              "@id": "http://example.org/id",
              "@graph": {"value": "x"}
            }
          })
        },
        "Odd framing test" => {
          input: %([
            {
              "http://example.org/claim": [
                {
                  "@graph": [
                    {
                      "@id": "http://example.org/1",
                      "https://example.com#test": [
                        {
                          "@value": "foo"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
          ),
          context: %( {
            "@version": 1.1,
            "@vocab": "https://example.com#",
            "ex": "http://example.org/",
            "claim": {
              "@id": "ex:claim",
              "@container": "@graph"
            },
            "id": "@id"
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "https://example.com#",
              "ex": "http://example.org/",
              "claim": {
                "@id": "ex:claim",
                "@container": "@graph"
              },
              "id": "@id"
            },
            "claim": {
              "id": "ex:1",
              "test": "foo"
            }
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
      end

      context "+ @index" do
        {
          "Compacts simple graph" => {
            input: %([{
              "http://example.org/input": [{
                "@index": "g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@index"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index"]}
              },
              "input": {
                "g1": {"value": "x"}
              }
            })
          },
          "Compacts simple graph with @set" => {
            input: %([{
              "http://example.org/input": [{
                "@index": "g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@index", "@set"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index", "@set"]}
              },
              "input": {
                "g1": [{"value": "x"}]
              }
            })
          },
          "Compacts simple graph with no @index" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@index", "@set"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index", "@set"]}
              },
              "input": {
                "@none": [{"value": "x"}]
              }
            })
          },
          "Does not compact graph with @id" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }],
                "@index": "g1",
                "@id": "http://example.org/id"
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@index"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index"]}
              },
              "input": {
                "@id": "http://example.org/id",
                "@index": "g1",
                "@graph": {"value": "x"}
              }
            })
          }
        }.each_pair do |title, params|
          it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
        end
      end

      context "+ @id" do
        {
          "Compacts simple graph" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@id"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]}
              },
              "input": {
                "@none": {"value": "x"}
              }
            })
          },
          "Compacts simple graph with @set" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@id", "@set"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id", "@set"]}
              },
              "input": {"@none": [{"value": "x"}]}
            })
          },
          "Compacts simple graph with @index" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }],
                "@index": "ndx"
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@id"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]}
              },
              "input": {
                "@none": {"value": "x"}
              }
            })
          },
          "Compacts graph with @id" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }],
                "@id": "http://example.org/id"
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@id"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]}
              },
              "input": {
                "http://example.org/id" : {"value": "x"}
              }
            })
          },
          "Compacts graph with @id and @set" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }],
                "@id": "http://example.org/id"
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@id", "@set"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id", "@set"]}
              },
              "input": {
                "http://example.org/id" : [{"value": "x"}]
              }
            })
          },
          "Compacts graph without @id" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@id"]}
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]}
              },
              "input": {
                "@none" : {"value": "x"}
              }
            })
          },
          "Compacts graph without @id using alias of @none" => {
            input: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]),
            context: %({
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@id"]},
              "none": "@none"
            }),
            output: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]},
                 "none": "@none"
              },
              "input": {
                "none" : {"value": "x"}
              }
            })
          }
        }.each_pair do |title, params|
          it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
        end
      end
    end

    context "@included" do
      {
        'Basic Included array': {
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/",
              "included": {"@id": "@included", "@container": "@set"}
            },
            "prop": "value",
            "included": [{
              "prop": "value2"
            }]
          }),
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "@included": [{
              "http://example.org/prop": [{"@value": "value2"}]
            }]
          }])
        },
        'Basic Included object': {
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": "value",
            "@included": {
              "prop": "value2"
            }
          }),
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "@included": [{
              "http://example.org/prop": [{"@value": "value2"}]
            }]
          }])
        },
        'Multiple properties mapping to @included are folded together': {
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/",
              "included1": "@included",
              "included2": "@included"
            },
            "included1": [
              {"prop": "value1"},
              {"prop": "value2"}
            ]
          }),
          input: %([{
            "@included": [
              {"http://example.org/prop": [{"@value": "value1"}]},
              {"http://example.org/prop": [{"@value": "value2"}]}
            ]
          }])
        },
        'Included containing @included': {
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": "value",
            "@included": {
              "prop": "value2",
              "@included": {
                "prop": "value3"
              }
            }
          }),
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "@included": [{
              "http://example.org/prop": [{"@value": "value2"}],
              "@included": [{
                "http://example.org/prop": [{"@value": "value3"}]
              }]
            }]
          }])
        },
        'Property value with @included': {
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": {
              "@type": "Foo",
              "@included": {
                "@type": "Bar"
              }
            }
          }),
          input: %([{
            "http://example.org/prop": [{
              "@type": ["http://example.org/Foo"],
              "@included": [{
                "@type": ["http://example.org/Bar"]
              }]
            }]
          }])
        }
      }.each do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "@nest" do
      {
        "Indexes to @nest for property with @nest" => {
          input: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [{"@value": "v2"}]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "p2": {"@nest": "@nest"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "p2": {"@nest": "@nest"}
            },
            "p1": "v1",
            "@nest": {
              "p2": "v2"
            }
          })
        },
        "Indexes to @nest for all properties with @nest" => {
          input: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [{"@value": "v2"}]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "p1": {"@nest": "@nest"},
            "p2": {"@nest": "@nest"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "p1": {"@nest": "@nest"},
              "p2": {"@nest": "@nest"}
            },
            "@nest": {
              "p1": "v1",
              "p2": "v2"
            }
          })
        },
        "Nests using alias of @nest" => {
          input: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [{"@value": "v2"}]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "nest": "@nest",
            "p2": {"@nest": "nest"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": "@nest",
              "p2": {"@nest": "nest"}
            },
            "p1": "v1",
            "nest": {
              "p2": "v2"
            }
          })
        },
        "Arrays of nested values" => {
          input: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [{"@value": "v2"}, {"@value": "v3"}]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "p2": {"@nest": "@nest"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "p2": {"@nest": "@nest"}
            },
            "p1": "v1",
            "@nest": {
              "p2": ["v2", "v3"]
            }
          })
        },
        "Nested @container: @list" => {
          input: %([{
            "http://example.org/list": [{"@list": [
              {"@value": "a"},
              {"@value": "b"}
            ]}]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "list": {"@container": "@list", "@nest": "nestedlist"},
            "nestedlist": "@nest"
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "list": {"@container": "@list", "@nest": "nestedlist"},
              "nestedlist": "@nest"
            },
            "nestedlist": {
              "list": ["a", "b"]
            }
          })
        },
        "Nested @container: @index" => {
          input: %([{
            "http://example.org/index": [
              {"@value": "a", "@index": "A"},
              {"@value": "b", "@index": "B"}
            ]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "index": {"@container": "@index", "@nest": "nestedindex"},
            "nestedindex": "@nest"
            }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "index": {"@container": "@index", "@nest": "nestedindex"},
              "nestedindex": "@nest"
            },
            "nestedindex": {
              "index": {
                "A": "a",
                "B": "b"
              }
            }
          })
        },
        "Nested @container: @language" => {
          input: %([{
            "http://example.org/container": [
              {"@value": "Die Königin", "@language": "de"},
              {"@value": "The Queen", "@language": "en"}
            ]
          }]),
          context: %({
            "@vocab": "http://example.org/",
            "container": {"@container": "@language", "@nest": "nestedlanguage"},
            "nestedlanguage": "@nest"
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "container": {"@container": "@language", "@nest": "nestedlanguage"},
              "nestedlanguage": "@nest"
            },
            "nestedlanguage": {
              "container": {
                "en": "The Queen",
                "de": "Die Königin"
              }
            }
          })
        },
        "Nested @container: @type" => {
          input: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type _:bar"}], "@type": ["_:bar"]},
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example.org/foo"]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "typemap": {"@container": "@type", "@nest": "nestedtypemap"},
            "nestedtypemap": "@nest"
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type", "@nest": "nestedtypemap"},
              "nestedtypemap": "@nest"
            },
            "nestedtypemap": {
              "typemap": {
                "_:bar": {"label": "Object with @type _:bar"},
                "http://example.org/foo": {"label": "Object with @type <foo>"}
              }
            }
          })
        },
        "Nested @container: @id" => {
          input: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with @id _:bar"}], "@id": "_:bar"},
              {"http://example/label": [{"@value": "Object with @id <foo>"}], "@id": "http://example.org/foo"}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "idmap": {"@container": "@id", "@nest": "nestedidmap"},
            "nestedidmap": "@nest"
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id", "@nest": "nestedidmap"},
              "nestedidmap": "@nest"
            },
            "nestedidmap": {
              "idmap": {
                "http://example.org/foo": {"label": "Object with @id <foo>"},
                "_:bar": {"label": "Object with @id _:bar"}
              }
            }
          })
        },
        "Multiple nest aliases" => {
          input: %({
            "http://example.org/foo": "bar",
            "http://example.org/bar": "foo"
          }),
          context: %({
            "@vocab": "http://example.org/",
            "foonest": "@nest",
            "barnest": "@nest",
            "foo": {"@nest": "foonest"},
            "bar": {"@nest": "barnest"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/",
              "foonest": "@nest",
              "barnest": "@nest",
              "foo": {"@nest": "foonest"},
              "bar": {"@nest": "barnest"}
            },
            "barnest": {"bar": "foo"},
            "foonest": {"foo": "bar"}
          })
        },
        "Nest term not defined" => {
          input: %({
            "http://example/foo": "bar"
          }),
          context: %({
            "term": {"@id": "http://example/foo", "@nest": "unknown"}
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        }
      }.each_pair do |title, params|
        it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "@graph" do
      {
        "Uses @graph given mutliple inputs" => {
          input: %([
            {"http://example.com/foo": ["foo"]},
            {"http://example.com/bar": ["bar"]}
          ]),
          context: %({"ex": "http://example.com/"}),
          output: %({
            "@context": {"ex": "http://example.com/"},
            "@graph": [
              {"ex:foo": "foo"},
              {"ex:bar": "bar"}
            ]
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact(params) }
      end
    end

    context "scoped context" do
      {
        "adding new term" => {
          input: %([{
            "http://example/foo": [{"http://example.org/bar": [{"@value": "baz"}]}]
          }]),
          context: %({
            "@vocab": "http://example/",
            "foo": {"@context": {"bar": "http://example.org/bar"}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "foo": {
              "bar": "baz"
            }
          })
        },
        "overriding a term" => {
          input: %([
            {
              "http://example/foo": [{"http://example/bar": [{"@id": "http://example/baz"}]}]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "foo": {"@context": {"bar": {"@type": "@id"}}},
            "bar": {"@type": "http://www.w3.org/2001/XMLSchema#string"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"bar": {"@type": "@id"}}},
              "bar": {"@type": "http://www.w3.org/2001/XMLSchema#string"}
            },
            "foo": {
              "bar": "http://example/baz"
            }
          })
        },
        "property and value with different terms mapping to the same expanded property" => {
          input: %([
            {
              "http://example/foo": [{
                "http://example/bar": [
                  {"@value": "baz"}
                ]}
              ]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "foo": {"@context": {"Bar": {"@id": "bar"}}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"Bar": {"@id": "bar"}}}
            },
            "foo": {
              "Bar": "baz"
            }
          })
        },
        "deep @context affects nested nodes" => {
          input: %([
            {
              "http://example/foo": [{
                "http://example/bar": [{
                  "http://example/baz": [{"@id": "http://example/buzz"}]
                }]
              }]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "foo": {"@context": {"baz": {"@type": "@vocab"}}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"baz": {"@type": "@vocab"}}}
            },
            "foo": {
              "bar": {
                "baz": "buzz"
              }
            }
          })
        },
        "scoped context layers on intemediate contexts" => {
          input: %([{
            "http://example/a": [{
              "http://example.com/c": [{"@value": "C in example.com"}],
              "http://example/b": [{
                "http://example.com/a": [{"@value": "A in example.com"}],
                "http://example.org/c": [{"@value": "C in example.org"}]
              }]
            }],
            "http://example/c": [{"@value": "C in example"}]
          }]),
          context: %({
            "@vocab": "http://example/",
            "b": {"@context": {"c": "http://example.org/c"}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "b": {"@context": {"c": "http://example.org/c"}}
            },
            "a": {
              "b": {
                "c": "C in example.org",
                "http://example.com/a": "A in example.com"
              },
              "http://example.com/c": "C in example.com"
            },
            "c": "C in example"
          })
        },
        "Raises InvalidTermDefinition if processingMode is 1.0" => {
          input: %([{
            "http://example/foo": [{"http://example.org/bar": [{"@value": "baz"}]}]
          }]),
          context: %({
            "@vocab": "http://example/",
            "foo": {"@context": {"bar": "http://example.org/bar"}}
          }),
          processingMode: 'json-ld-1.0',
          validate: true,
          exception: JSON::LD::JsonLdError::InvalidTermDefinition
        },
        'Scoped on id map': {
          output: %({
            "@context": {
              "@version": 1.1,
              "schema": "http://schema.org/",
              "name": "schema:name",
              "body": "schema:articleBody",
              "words": "schema:wordCount",
              "post": {
                "@id": "schema:blogPost",
                "@container": "@id",
                "@context": {
                  "@base": "http://example.com/posts/"
                }
              }
            },
            "@id": "http://example.com/",
            "@type": "schema:Blog",
            "name": "World Financial News",
            "post": {
              "1/en": {
                "body": "World commodities were up today with heavy trading of crude oil...",
                "words": 1539
              },
              "1/de": {
                "body": "Die Werte an Warenbörsen stiegen im Sog eines starken Handels von Rohöl...",
                "words": 1204
              }
            }
          }),
          input: %([{
            "@id": "http://example.com/",
            "@type": ["http://schema.org/Blog"],
            "http://schema.org/name": [{"@value": "World Financial News"}],
            "http://schema.org/blogPost": [{
              "@id": "http://example.com/posts/1/en",
              "http://schema.org/articleBody": [
                {"@value": "World commodities were up today with heavy trading of crude oil..."}
              ],
              "http://schema.org/wordCount": [{"@value": 1539}]
            }, {
              "@id": "http://example.com/posts/1/de",
              "http://schema.org/articleBody": [
                {"@value": "Die Werte an Warenbörsen stiegen im Sog eines starken Handels von Rohöl..."}
              ],
              "http://schema.org/wordCount": [{"@value": 1204}]
            }]
          }])
        }
      }.each_pair do |title, params|
        it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "scoped context on @type" do
      {
        "adding new term" => {
          input: %([
            {
              "http://example/a": [{
                "@type": ["http://example/Foo"],
                "http://example.org/bar": [{"@value": "baz"}]
              }]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "Foo": {"@context": {"bar": "http://example.org/bar"}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "Foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "a": {"@type": "Foo", "bar": "baz"}
          })
        },
        "overriding a term" => {
          input: %([
            {
              "http://example/a": [{
                "@type": ["http://example/Foo"],
                "http://example/bar": [{"@id": "http://example/baz"}]
              }]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "Foo": {"@context": {"bar": {"@type": "@id"}}},
            "bar": {"@type": "http://www.w3.org/2001/XMLSchema#string"}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "Foo": {"@context": {"bar": {"@type": "@id"}}},
              "bar": {"@type": "http://www.w3.org/2001/XMLSchema#string"}
            },
            "a": {"@type": "Foo", "bar": "http://example/baz"}
          })
        },
        "alias of @type" => {
          input: %([
            {
              "http://example/a": [{
                "@type": ["http://example/Foo"],
                "http://example.org/bar": [{"@value": "baz"}]
              }]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "type": "@type",
            "Foo": {"@context": {"bar": "http://example.org/bar"}}
            }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "type": "@type",
              "Foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "a": {"type": "Foo", "bar": "baz"}
          })
        },
        "deep @context does not affect nested nodes" => {
          input: %([
            {
              "@type": ["http://example/Foo"],
              "http://example/bar": [{
                "http://example/baz": [{"@id": "http://example/buzz"}]
              }]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "Foo": {"@context": {"baz": {"@type": "@vocab"}}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "Foo": {"@context": {"baz": {"@type": "@vocab"}}}
            },
            "@type": "Foo",
            "bar": {"baz": {"@id": "http://example/buzz"}}
          })
        },
        "scoped context layers on intemediate contexts" => {
          input: %([{
            "http://example/a": [{
              "@type": ["http://example/B"],
              "http://example.com/a": [{"@value": "A in example.com"}],
              "http://example.org/c": [{"@value": "C in example.org"}]
            }],
            "http://example/c": [{"@value": "C in example"}]
          }]),
          context: %({
            "@vocab": "http://example/",
            "B": {"@context": {"c": "http://example.org/c"}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "B": {"@context": {"c": "http://example.org/c"}}
            },
            "a": {
              "@type": "B",
              "c": "C in example.org",
              "http://example.com/a": "A in example.com"
            },
            "c": "C in example"
          })
        },
        "orders lexicographically" => {
          input: %([{
            "@type": ["http://example/t2", "http://example/t1"],
            "http://example.org/foo": [
              {"@id": "urn:bar"}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "t1": {"@context": {"foo": {"@id": "http://example.com/foo"}}},
            "t2": {"@context": {"foo": {"@id": "http://example.org/foo", "@type": "@id"}}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "t1": {"@context": {"foo": {"@id": "http://example.com/foo"}}},
              "t2": {"@context": {"foo": {"@id": "http://example.org/foo", "@type": "@id"}}}
            },
            "@type": ["t2", "t1"],
            "foo": "urn:bar"
          })
        },
        "with @container: @type" => {
          input: %([{
            "http://example/typemap": [
              {"http://example.org/a": [{"@value": "Object with @type <Type>"}], "@type": ["http://example/Type"]}
            ]
          }]),
          context: %({
            "@vocab": "http://example/",
            "typemap": {"@container": "@type"},
            "Type": {"@context": {"a": "http://example.org/a"}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"},
              "Type": {"@context": {"a": "http://example.org/a"}}
            },
            "typemap": {
              "Type": {"a": "Object with @type <Type>"}
            }
          })
        },
        "Raises InvalidTermDefinition if processingMode is 1.0" => {
          input: %([
            {
              "http://example/a": [{
                "@type": ["http://example/Foo"],
                "http://example.org/bar": [{"@value": "baz"}]
              }]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "Foo": {"@context": {"bar": "http://example.org/bar"}}
          }),
          processingMode: 'json-ld-1.0',
          validate: true,
          exception: JSON::LD::JsonLdError::InvalidTermDefinition
        },
        "applies context for all values" => {
          input: %([
            {
              "@id": "http://example.org/id",
              "@type": ["http://example/type"],
              "http://example/a": [{
                "@id": "http://example.org/Foo",
                "@type": ["http://example/Foo"],
                "http://example/bar": [{"@id": "http://example.org/baz"}]
              }]
            }
          ]),
          context: %({
            "@vocab": "http://example/",
            "id": "@id",
            "type": "@type",
            "Foo": {"@context": {"id": null, "type": null}}
          }),
          output: %({
            "@context": {
              "@vocab": "http://example/",
              "id": "@id",
              "type": "@type",
              "Foo": {"@context": {"id": null, "type": null}}
            },
            "id": "http://example.org/id",
            "type": "http://example/type",
            "a": {
              "@id": "http://example.org/Foo",
              "@type": "Foo",
              "bar": {"@id": "http://example.org/baz"}
            }
          })
        }
      }.each_pair do |title, params|
        it(title) { run_compact({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "compact IRI selection" do
      {
        "does not compact using expanded term in 1.0" => {
          input: %({"http://example.org/foo": "term"}),
          context: %({"ex": {"@id": "http://example.org/"}}),
          output: %({
            "@context": {"ex": {"@id": "http://example.org/"}},
            "http://example.org/foo": "term"
          }),
          processingMode: "json-ld-1.0"
        },
        "does not compact using expanded term in 1.1" => {
          input: %({"http://example.org/foo": "term"}),
          context: %({"ex": {"@id": "http://example.org/"}}),
          output: %({
            "@context": {"ex": {"@id": "http://example.org/"}},
            "http://example.org/foo": "term"
          }),
          processingMode: "json-ld-1.1"
        },
        "does not compact using simple term not ending in gen-delim" => {
          input: %({"http://example.org/foo": "term"}),
          context: %({"ex": "http://example.org/f"}),
          output: %({
            "@context": {"ex": "http://example.org/f"},
            "http://example.org/foo": "term"
          })
        },
        "compacts using simple term ending in gen-delim ('/')" => {
          input: %({"http://example.org/foo": "term"}),
          context: %({"ex": "http://example.org/"}),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "ex:foo": "term"
          })
        },
        "compacts using simple term ending in gen-delim (':')" => {
          input: %({"http://example.org/foo:bar": "term"}),
          context: %({"ex": "http://example.org/foo:"}),
          output: %({
            "@context": {"ex": "http://example.org/foo:"},
            "ex:bar": "term"
          })
        },
        "compacts using simple term ending in gen-delim ('?')" => {
          input: %({"http://example.org/foo?bar": "term"}),
          context: %({"ex": "http://example.org/foo?"}),
          output: %({
            "@context": {"ex": "http://example.org/foo?"},
            "ex:bar": "term"
          })
        },
        "compacts using simple term ending in gen-delim ('#')" => {
          input: %({"http://example.org/foo#bar": "term"}),
          context: %({"ex": "http://example.org/foo#"}),
          output: %({
            "@context": {"ex": "http://example.org/foo#"},
            "ex:bar": "term"
          })
        },
        "compacts using simple term ending in gen-delim ('[')" => {
          input: %({"http://example.org/foo[bar": "term"}),
          context: %({"ex": "http://example.org/foo["}),
          output: %({
            "@context": {"ex": "http://example.org/foo["},
            "ex:bar": "term"
          })
        },
        "compacts using simple term ending in gen-delim (']')" => {
          input: %({"http://example.org/foo]bar": "term"}),
          context: %({"ex": "http://example.org/foo]"}),
          output: %({
            "@context": {"ex": "http://example.org/foo]"},
            "ex:bar": "term"
          })
        },
        "compacts using simple term ending in gen-delim ('@')" => {
          input: %({"http://example.org/foo@bar": "term"}),
          context: %({"ex": "http://example.org/foo@"}),
          output: %({
            "@context": {"ex": "http://example.org/foo@"},
            "ex:bar": "term"
          })
        },
        "compacts using base if @vocab: relative" => {
          input: %({"http://example.org/foo/bar": "term"}),
          context: %({"@base": "http://example.org/foo/", "@vocab": ""}),
          output: %({
            "@context": {"@base": "http://example.org/foo/", "@vocab": ""},
            "bar": "term"
          })
        }
      }.each do |title, params|
        it(title) { run_compact(params) }
      end
    end
  end

  context "html" do
    {
      'Compacts embedded JSON-LD script element': {
        input: %(
        <html>
          <head>
            <script type="application/ld+json">
            {
              "@context": {
                "foo": {"@id": "http://example.com/foo", "@container": "@list"}
              },
              "foo": [{"@value": "bar"}]
            }
            </script>
          </head>
        </html>),
        context: %({"foo": {"@id": "http://example.com/foo", "@container": "@list"}}),
        output: %({
          "@context": {
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          },
          "foo": ["bar"]
        })
      },
      'Compacts first script element': {
        input: %(
        <html>
          <head>
            <script type="application/ld+json">
            {
              "@context": {
                "foo": {"@id": "http://example.com/foo", "@container": "@list"}
              },
              "foo": [{"@value": "bar"}]
            }
            </script>
            <script type="application/ld+json">
            {
              "@context": {"ex": "http://example.com/"},
              "@graph": [
                {"ex:foo": {"@value": "foo"}},
                {"ex:bar": {"@value": "bar"}}
              ]
            }
            </script>
          </head>
        </html>),
        context: %({"foo": {"@id": "http://example.com/foo", "@container": "@list"}}),
        output: %({
          "@context": {
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          },
          "foo": ["bar"]
        })
      },
      'Compacts targeted script element': {
        input: %(
        <html>
          <head>
            <script id="first" type="application/ld+json">
            {
              "@context": {
                "foo": {"@id": "http://example.com/foo", "@container": "@list"}
              },
              "foo": [{"@value": "bar"}]
            }
            </script>
            <script id="second" type="application/ld+json">
            {
              "@context": {"ex": "http://example.com/"},
              "@graph": [
                {"ex:foo": {"@value": "foo"}},
                {"ex:bar": {"@value": "bar"}}
              ]
            }
            </script>
          </head>
        </html>),
        context: %({"ex": "http://example.com/"}),
        output: %({
          "@context": {"ex": "http://example.com/"},
          "@graph": [
            {"ex:foo": "foo"},
            {"ex:bar": "bar"}
          ]
        }),
        base: "http://example.org/doc#second"
      },
      'Compacts all script elements with extractAllScripts option': {
        input: %(
        <html>
          <head>
            <script type="application/ld+json">
            {
              "@context": {
                "foo": {"@id": "http://example.com/foo", "@container": "@list"}
              },
              "foo": [{"@value": "bar"}]
            }
            </script>
            <script type="application/ld+json">
            {
              "@context": {"ex": "http://example.com/"},
              "@graph": [
                {"ex:foo": {"@value": "foo"}},
                {"ex:bar": {"@value": "bar"}}
              ]
            }
            </script>
          </head>
        </html>),
        context: %({
          "ex": "http://example.com/",
          "foo": {"@id": "http://example.com/foo", "@container": "@list"}
        }),
        output: %({
          "@context": {
            "ex": "http://example.com/",
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          },
          "@graph": [
            {"foo": ["bar"]},
            {
              "@graph": [
                {"ex:foo": "foo"},
                {"ex:bar": "bar"}
              ]
            }
          ]
        }),
        extractAllScripts: true
      }
    }.each do |title, params|
      it(title) do
        params[:input] = StringIO.new(params[:input])
        params[:input].send(:define_singleton_method, :content_type) { "text/html" }
        run_compact params.merge(validate: true)
      end
    end
  end

  context "JSON-LD-star" do
    {
      'subject-iii': {
        input: %([{
          "@id": {
            "@id": "http://example/s1",
            "http://example/p1": [{"@id": "http://example/o1"}]
          },
          "http://example/p": [{"@id": "http://example/o"}]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
         "@context": {"ex": "http://example/"},
         "@id": {
           "@id": "ex:s1",
           "ex:p1": {"@id": "ex:o1"}
         },
         "ex:p": {"@id": "ex:o"}
       })
      },
      'subject-iib': {
        input: %([{
          "@id": {
            "@id": "http://example/s1",
            "http://example/p1": [{"@id": "_:o1"}]
          },
          "http://example/p": [{"@id": "http://example/o"}]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "ex:s1",
            "ex:p1": {"@id": "_:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-iil': {
        input: %([{
          "@id": {
            "@id": "http://example/s1",
            "http://example/p1": [{"@value": "o1"}]
          },
          "http://example/p": [{"@id": "http://example/o"}]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "ex:s1",
            "ex:p1": "o1"
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-bii': {
        input: %([{
          "@id": {
            "@id": "_:s1",
            "http://example/p1": [{"@id": "http://example/o1"}]
          },
          "http://example/p": [{"@id": "http://example/o"}]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "_:s1",
            "ex:p1": {"@id": "ex:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-bib': {
        input: %([{
          "@id": {
            "@id": "_:s1",
            "http://example/p1": [{"@id": "_:o1"}]
          },
          "http://example/p": [{"@id": "http://example/o"}]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "_:s1",
            "ex:p1": {"@id": "_:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-bil': {
        input: %([{
          "@id": {
            "@id": "_:s1",
            "http://example/p1": [{"@value": "o1"}]
          },
          "http://example/p": [{"@id": "http://example/o"}]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "_:s1",
            "ex:p1": "o1"
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'object-iii': {
        input: %([{
          "@id": "http://example/s",
          "http://example/p": [{
            "@id": {
              "@id": "http://example/s1",
              "http://example/p1": [{"@id": "http://example/o1"}]
            }
          }]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": "ex:s",
          "ex:p": {
            "@id": {
              "@id": "ex:s1",
              "ex:p1": {"@id": "ex:o1"}
            }
          }
        })
      },
      'object-iib': {
        input: %([{
          "@id": "http://example/s",
          "http://example/p": [{
            "@id": {
              "@id": "http://example/s1",
              "http://example/p1": [{"@id": "_:o1"}]
            }
          }]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": "ex:s",
          "ex:p": {
            "@id": {
              "@id": "ex:s1",
              "ex:p1": {"@id": "_:o1"}
            }
          }
        })
      },
      'object-iil': {
        input: %([{
          "@id": "http://example/s",
          "http://example/p": [{
            "@id": {
              "@id": "http://example/s1",
              "http://example/p1": [{"@value": "o1"}]
            }
          }]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": "ex:s",
          "ex:p": {
            "@id": {
              "@id": "ex:s1",
              "ex:p1": "o1"
            }
          }
        })
      },
      'recursive-subject': {
        input: %([{
          "@id": {
            "@id": {
              "@id": "http://example/s2",
              "http://example/p2": [{"@id": "http://example/o2"}]
            },
            "http://example/p1": [{"@id": "http://example/o1"}]
          },
          "http://example/p": [{"@id": "http://example/o"}]
        }]),
        context: %({"ex": "http://example/"}),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": {
              "@id": "ex:s2",
              "ex:p2": {"@id": "ex:o2"}
            },
            "ex:p1": {"@id": "ex:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      }
    }.each do |name, params|
      it(name) { run_compact(params.merge(rdfstar: true)) }
    end
  end

  context "problem cases" do
    {
      'issue json-ld-framing#64': {
        input: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "http://example.org/vocab#"
          },
          "@id": "http://example.org/1",
          "@type": "HumanMadeObject",
          "produced_by": {
            "@type": "Production",
            "_label": "Top Production",
            "part": {
              "@type": "Production",
              "_label": "Test Part"
            }
          }
        }),
        context: %({
          "@version": 1.1,
          "@vocab": "http://example.org/vocab#",
          "Production": {
            "@context": {
              "part": {
                "@type": "@id",
                "@container": "@set"
              }
            }
          }
        }),
        output: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "http://example.org/vocab#",
            "Production": {
              "@context": {
                "part": {
                  "@type": "@id",
                  "@container": "@set"
                }
              }
            }
          },
          "@id": "http://example.org/1",
          "@type": "HumanMadeObject",
          "produced_by": {
            "@type": "Production",
            "part": [{
              "@type": "Production",
              "_label": "Test Part"
            }],
            "_label": "Top Production"
          }
        }),
        processingMode: "json-ld-1.1"
      },
      "ruby-rdf/json-ld#62": {
        input: %({
          "@context": {
            "@vocab": "http://schema.org/"
          },
          "@type": "Event",
          "location": {
            "@id": "http://kg.artsdata.ca/resource/K11-200"
          }
        }),
        context: %({
          "@context": {
            "@vocab": "http://schema.org/",
            "location": {
              "@type": "@id",
              "@container": "@type"
            }
          }
        }),
        output: %({
          "@context": {
            "@vocab": "http://schema.org/",
            "location": {
              "@type": "@id",
              "@container": "@type"
            }
          },
          "@type": "Event",
          "location": {
            "@none": "http://kg.artsdata.ca/resource/K11-200"
          }
        }),
        processingMode: "json-ld-1.1"
      }
    }.each do |title, params|
      it title do
        run_compact(params)
      end
    end
  end

  def run_compact(params)
    input = params[:input]
    output = params[:output]
    context = params[:context]
    params[:base] ||= nil
    context ||= output # Since it will have the context
    input = JSON.parse(input) if input.is_a?(String)
    output = JSON.parse(output) if output.is_a?(String)
    context = JSON.parse(context) if context.is_a?(String)
    context = context['@context'] if context.key?('@context')
    pending params.fetch(:pending, "test implementation") unless input
    if params[:exception]
      expect { JSON::LD::API.compact(input, context, logger: logger, **params) }.to raise_error(params[:exception])
    else
      jld = nil
      if params[:write]
        expect do
          jld = JSON::LD::API.compact(input, context, logger: logger, **params)
        end.to write(params[:write]).to(:error)
      else
        expect { jld = JSON::LD::API.compact(input, context, logger: logger, **params) }.not_to write.to(:error)
      end

      expect(jld).to produce_jsonld(output, logger)

      # Compare expanded jld/output too to make sure list values remain ordered
      exp_jld = JSON::LD::API.expand(jld, processingMode: 'json-ld-1.1', rdfstar: params[:rdfstar])
      exp_output = JSON::LD::API.expand(output, processingMode: 'json-ld-1.1', rdfstar: params[:rdfstar])
      expect(exp_jld).to produce_jsonld(exp_output, logger)
    end
  end
end
