# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  let(:logger) {RDF::Spec.logger}

  describe ".expand" do
    {
      "empty doc" => {
        input: {},
        output: []
      },
      "@list coercion" => {
        input: {
          "@context" => {
            "foo" => {"@id" => "http://example.com/foo", "@container" => "@list"}
          },
          "foo" => [{"@value" => "bar"}]
        },
        output: [{
          "http://example.com/foo" => [{"@list" => [{"@value" => "bar"}]}]
        }]
      },
      "native values in list" => {
        input: {
          "http://example.com/foo" => {"@list" => [1, 2]}
        },
        output: [{
          "http://example.com/foo" => [{"@list" => [{"@value" => 1}, {"@value" => 2}]}]
        }]
      },
      "@graph" => {
        input: {
          "@context" => {"ex" => "http://example.com/"},
          "@graph" => [
            {"ex:foo"  => {"@value" => "foo"}},
            {"ex:bar" => {"@value" => "bar"}}
          ]
        },
        output: [
          {"http://example.com/foo" => [{"@value" => "foo"}]},
          {"http://example.com/bar" => [{"@value" => "bar"}]}
        ]
      },
      "@graph value (expands to array form)" => {
        input: {
          "@context" => {"ex" => "http://example.com/"},
          "ex:p" => {
            "@id" => "ex:Sub1",
            "@graph" => {
              "ex:q" => "foo"
            }
          }
        },
        output: [{
          "http://example.com/p" => [{
            "@id" => "http://example.com/Sub1",
            "@graph" => [{
              "http://example.com/q" => [{"@value" => "foo"}],
            }]
          }]
        }]
      },
      "@type with CURIE" => {
        input: {
          "@context" => {"ex" => "http://example.com/"},
          "@type" => "ex:type"
        },
        output: [
          {"@type" => ["http://example.com/type"]}
        ]
      },
      "@type with CURIE and muliple values" => {
        input: {
          "@context" => {"ex" => "http://example.com/"},
          "@type" => ["ex:type1", "ex:type2"]
        },
        output: [
          {"@type" => ["http://example.com/type1", "http://example.com/type2"]}
        ]
      },
      "@value with false" => {
        input: {"http://example.com/ex" => {"@value" => false}},
        output: [{"http://example.com/ex" => [{"@value" => false}]}]
      }
    }.each_pair do |title, params|
      it(title) {run_expand params}
    end

    context "with relative IRIs" do
      {
        "base" => {
          input: {
            "@id" => "",
            "@type" => "http://www.w3.org/2000/01/rdf-schema#Resource"
          },
          output: [{
            "@id" => "http://example.org/",
            "@type" => ["http://www.w3.org/2000/01/rdf-schema#Resource"]
          }]
        },
        "relative" => {
          input: {
            "@id" => "a/b",
            "@type" => "http://www.w3.org/2000/01/rdf-schema#Resource"
          },
          output: [{
            "@id" => "http://example.org/a/b",
            "@type" => ["http://www.w3.org/2000/01/rdf-schema#Resource"]
          }]
        },
        "hash" => {
          input: {
            "@id" => "#a",
            "@type" => "http://www.w3.org/2000/01/rdf-schema#Resource"
          },
          output: [{
            "@id" => "http://example.org/#a",
            "@type" => ["http://www.w3.org/2000/01/rdf-schema#Resource"]
          }]
        },
        "unmapped @id" => {
          input: {
            "http://example.com/foo" => {"@id" => "bar"}
          },
          output: [{
            "http://example.com/foo" => [{"@id" => "http://example.org/bar"}]
          }]
        },
      }.each do |title, params|
        it(title) {run_expand params.merge(base: "http://example.org/")}
      end
    end

    context "keyword aliasing" do
      {
        "@id" => {
          input: {
            "@context" => {"id" => "@id"},
            "id" => "",
            "@type" => "http://www.w3.org/2000/01/rdf-schema#Resource"
          },
          output: [{
            "@id" => "",
            "@type" =>[ "http://www.w3.org/2000/01/rdf-schema#Resource"]
          }]
        },
        "@type" => {
          input: {
            "@context" => {"type" => "@type"},
            "type" => "http://www.w3.org/2000/01/rdf-schema#Resource",
            "http://example.com/foo" => {"@value" => "bar", "type" => "http://example.com/baz"}
          },
          output: [{
            "@type" => ["http://www.w3.org/2000/01/rdf-schema#Resource"],
            "http://example.com/foo" => [{"@value" => "bar", "@type" => "http://example.com/baz"}]
          }]
        },
        "@language" => {
          input: {
            "@context" => {"language" => "@language"},
            "http://example.com/foo" => {"@value" => "bar", "language" => "baz"}
          },
          output: [{
            "http://example.com/foo" => [{"@value" => "bar", "@language" => "baz"}]
          }]
        },
        "@value" => {
          input: {
            "@context" => {"literal" => "@value"},
            "http://example.com/foo" => {"literal" => "bar"}
          },
          output: [{
            "http://example.com/foo" => [{"@value" => "bar"}]
          }]
        },
        "@list" => {
          input: {
            "@context" => {"list" => "@list"},
            "http://example.com/foo" => {"list" => ["bar"]}
          },
          output: [{
            "http://example.com/foo" => [{"@list" => [{"@value" => "bar"}]}]
          }]
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "native types" do
      {
        "true" => {
          input: {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => true
          },
          output: [{
            "http://example.org/vocab#bool" => [{"@value" => true}]
          }]
        },
        "false" => {
          input: {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => false
          },
          output: [{
            "http://example.org/vocab#bool" => [{"@value" => false}]
          }]
        },
        "double" => {
          input: {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double" => 1.23
          },
          output: [{
            "http://example.org/vocab#double" => [{"@value" => 1.23}]
          }]
        },
        "double-zero" => {
          input: {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double-zero" => 0.0e0
          },
          output: [{
            "http://example.org/vocab#double-zero" => [{"@value" => 0.0e0}]
          }]
        },
        "integer" => {
          input: {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:integer" => 123
          },
          output: [{
            "http://example.org/vocab#integer" => [{"@value" => 123}]
          }]
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "coerced typed values" do
      {
        "boolean" => {
          input: {
            "@context" => {"foo" => {"@id" => "http://example.org/foo", "@type" => "http://www.w3.org/2001/XMLSchema#boolean"}},
            "foo" => "true"
          },
          output: [{
            "http://example.org/foo" => [{"@value" => "true", "@type" => "http://www.w3.org/2001/XMLSchema#boolean"}]
          }]
        },
        "date" => {
          input: {
            "@context" => {"foo" => {"@id" => "http://example.org/foo", "@type" => "http://www.w3.org/2001/XMLSchema#date"}},
            "foo" => "2011-03-26"
          },
          output: [{
            "http://example.org/foo" => [{"@value" => "2011-03-26", "@type" => "http://www.w3.org/2001/XMLSchema#date"}]
          }]
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "null" do
      {
        "value" => {
          input: {"http://example.com/foo" => nil},
          output: []
        },
        "@value" => {
          input: {"http://example.com/foo" => {"@value" => nil}},
          output: []
        },
        "@value and non-null @type" => {
          input: {"http://example.com/foo" => {"@value" => nil, "@type" => "http://type"}},
          output: []
        },
        "@value and non-null @language" => {
          input: {"http://example.com/foo" => {"@value" => nil, "@language" => "en"}},
          output: []
        },
        "array with null elements" => {
          input: {
            "http://example.com/foo" => [nil]
          },
          output: [{
            "http://example.com/foo" => []
          }]
        },
        "@set with null @value" => {
          input: {
            "http://example.com/foo" => [
              {"@value" => nil, "@type" => "http://example.org/Type"}
            ]
          },
          output: [{
            "http://example.com/foo" => []
          }]
        }
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "default language" do
      {
        "value with coerced null language" => {
          input: {
            "@context" => {
              "@language" => "en",
              "ex" => "http://example.org/vocab#",
              "ex:german" => { "@language" => "de" },
              "ex:nolang" => { "@language" => nil }
            },
            "ex:german" => "german",
            "ex:nolang" => "no language"
          },
          output: [
            {
              "http://example.org/vocab#german" => [{"@value" => "german", "@language" => "de"}],
              "http://example.org/vocab#nolang" => [{"@value" => "no language"}]
            }
          ]
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "default vocabulary" do
      {
        "property" => {
          input: {
            "@context" => {"@vocab" => "http://example.com/"},
            "verb" => {"@value" => "foo"}
          },
          output: [{
            "http://example.com/verb" => [{"@value" => "foo"}]
          }]
        },
        "datatype" => {
          input: {
            "@context" => {"@vocab" => "http://example.com/"},
            "http://example.org/verb" => {"@value" => "foo", "@type" => "string"}
          },
          output: [
            "http://example.org/verb" => [{"@value" => "foo", "@type" => "http://example.com/string"}]
          ]
        },
        "expand-0028" => {
          input: {
            "@context" => {
              "@vocab" => "http://example.org/vocab#",
              "date" => { "@type" => "dateTime" }
            },
            "@id" => "example1",
            "@type" => "test",
            "date" => "2011-01-25T00:00:00Z",
            "embed" => {
              "@id" => "example2",
              "expandedDate" => { "@value" => "2012-08-01T00:00:00Z", "@type" => "dateTime" }
            }
          },
          output: [
            {
              "@id" => "http://foo/bar/example1",
              "@type" => ["http://example.org/vocab#test"],
              "http://example.org/vocab#date" => [
                {
                  "@value" => "2011-01-25T00:00:00Z",
                  "@type" => "http://example.org/vocab#dateTime"
                }
              ],
              "http://example.org/vocab#embed" => [
                {
                  "@id" => "http://foo/bar/example2",
                  "http://example.org/vocab#expandedDate" => [
                    {
                      "@value" => "2012-08-01T00:00:00Z",
                      "@type" => "http://example.org/vocab#dateTime"
                    }
                  ]
                }
              ]
            }
          ]
        }
      }.each do |title, params|
        it(title) {run_expand params.merge(base: "http://foo/bar/")}
      end
    end

    context "unmapped properties" do
      {
        "unmapped key" => {
          input: {
            "foo" => "bar"
          },
          output: []
        },
        "unmapped @type as datatype" => {
          input: {
            "http://example.com/foo" => {"@value" => "bar", "@type" => "baz"}
          },
          output: [{
            "http://example.com/foo" => [{"@value" => "bar", "@type" => "http://example/baz"}]
          }]
        },
        "unknown keyword" => {
          input: {
            "@foo" => "bar"
          },
          output: []
        },
        "value" => {
          input: {
            "@context" => {"ex" => {"@id" => "http://example.org/idrange", "@type" => "@id"}},
            "@id" => "http://example.org/Subj",
            "idrange" => "unmapped"
          },
          output: []
        },
        "context reset" => {
          input: {
            "@context" => {"ex" => "http://example.org/", "prop" => "ex:prop"},
            "@id" => "http://example.org/id1",
            "prop" => "prop",
            "ex:chain" => {
              "@context" => nil,
              "@id" => "http://example.org/id2",
              "prop" => "prop"
            }
          },
          output: [{
            "@id" => "http://example.org/id1",
            "http://example.org/prop" => [{"@value" => "prop"}],
            "http://example.org/chain" => [{"@id" => "http://example.org/id2"}]
          }
        ]}
      }.each do |title, params|
        it(title) {run_expand params.merge(base: "http://example/")}
      end
    end

    context "@container: @index" do
      {
        "string annotation" => {
          input: {
            "@context" => {
              "container" => {
                "@id" => "http://example.com/container",
                "@container" => "@index"
              }
            },
            "@id" => "http://example.com/annotationsTest",
            "container" => {
              "en" => "The Queen",
              "de" => [ "Die Königin", "Ihre Majestät" ]
            }
          },
          output: [
            {
              "@id" => "http://example.com/annotationsTest",
              "http://example.com/container" => [
                {"@value" => "Die Königin", "@index" => "de"},
                {"@value" => "Ihre Majestät", "@index" => "de"},
                {"@value" => "The Queen", "@index" => "en"}
              ]
            }
          ]
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "@container: @list" do
      {
        "empty" => {
          input: {"http://example.com/foo" => {"@list" => []}},
          output: [{"http://example.com/foo" => [{"@list" => []}]}]
        },
        "coerced empty" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@container" => "@list"}},
            "http://example.com/foo" => []
          },
          output: [{"http://example.com/foo" => [{"@list" => []}]}]
        },
        "coerced single element" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@container" => "@list"}},
            "http://example.com/foo" => [ "foo" ]
          },
          output: [{"http://example.com/foo" => [{"@list" => [{"@value" => "foo"}]}]}]
        },
        "coerced multiple elements" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@container" => "@list"}},
            "http://example.com/foo" => [ "foo", "bar" ]
          },
          output: [{
            "http://example.com/foo" => [{"@list" => [ {"@value" => "foo"}, {"@value" => "bar"} ]}]
          }]
        },
        "native values in list" => {
          input: {
            "http://example.com/foo" => {"@list" => [1, 2]}
          },
          output: [{
            "http://example.com/foo" => [{"@list" => [{"@value" => 1}, {"@value" => 2}]}]
          }]
        },
        "explicit list with coerced @id values" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@type" => "@id"}},
            "http://example.com/foo" => {"@list" => ["http://foo", "http://bar"]}
          },
          output: [{
            "http://example.com/foo" => [{"@list" => [{"@id" => "http://foo"}, {"@id" => "http://bar"}]}]
          }]
        },
        "explicit list with coerced datatype values" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@type" => RDF::XSD.date.to_s}},
            "http://example.com/foo" => {"@list" => ["2012-04-12"]}
          },
          output: [{
            "http://example.com/foo" => [{"@list" => [{"@value" => "2012-04-12", "@type" => RDF::XSD.date.to_s}]}]
          }]
        },
        "expand-0004" => {
          input: %({
            "@context": {
              "mylist1": {"@id": "http://example.com/mylist1", "@container": "@list"},
              "mylist2": {"@id": "http://example.com/mylist2", "@container": "@list"},
              "myset2": {"@id": "http://example.com/myset2", "@container": "@set"},
              "myset3": {"@id": "http://example.com/myset3", "@container": "@set"}
            },
            "http://example.org/property": { "@list": "one item" }
          }),
          output: %([
            {
              "http://example.org/property": [
                {
                  "@list": [
                    {
                      "@value": "one item"
                    }
                  ]
                }
              ]
            }
          ])
        },
        "@list containing @list" => {
          input: {
            "http://example.com/foo" => {"@list" => [{"@list" => ["baz"]}]}
          },
          exception: JSON::LD::JsonLdError::ListOfLists
        },
        "@list containing @list (with coercion)" => {
          input: {
            "@context" => {"foo" => {"@id" => "http://example.com/foo", "@container" => "@list"}},
            "foo" => [{"@list" => ["baz"]}]
          },
          exception: JSON::LD::JsonLdError::ListOfLists
        },
        "coerced @list containing an array" => {
          input: {
            "@context" => {"foo" => {"@id" => "http://example.com/foo", "@container" => "@list"}},
            "foo" => [["baz"]]
          },
          exception: JSON::LD::JsonLdError::ListOfLists
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "@container: @set" do
      {
        "empty" => {
          input: {
            "http://example.com/foo" => {"@set" => []}
          },
          output: [{
            "http://example.com/foo" => []
          }]
        },
        "coerced empty" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@container" => "@set"}},
            "http://example.com/foo" => []
          },
          output: [{
            "http://example.com/foo" => []
          }]
        },
        "coerced single element" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@container" => "@set"}},
            "http://example.com/foo" => [ "foo" ]
          },
          output: [{
            "http://example.com/foo" => [ {"@value" => "foo"} ]
          }]
        },
        "coerced multiple elements" => {
          input: {
            "@context" => {"http://example.com/foo" => {"@container" => "@set"}},
            "http://example.com/foo" => [ "foo", "bar" ]
          },
          output: [{
            "http://example.com/foo" => [ {"@value" => "foo"}, {"@value" => "bar"} ]
          }]
        },
        "array containing set" => {
          input: {
            "http://example.com/foo" => [{"@set" => []}]
          },
          output: [{
            "http://example.com/foo" => []
          }]
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "@container: @language" do
      {
        "simple map" => {
          input: {
            "@context" => {
              "vocab" => "http://example.com/vocab/",
              "label" => {
                "@id" => "vocab:label",
                "@container" => "@language"
              }
            },
            "@id" => "http://example.com/queen",
            "label" => {
              "en" => "The Queen",
              "de" => [ "Die Königin", "Ihre Majestät" ]
            }
          },
          output: [
            {
              "@id" => "http://example.com/queen",
              "http://example.com/vocab/label" => [
                {"@value" => "Die Königin", "@language" => "de"},
                {"@value" => "Ihre Majestät", "@language" => "de"},
                {"@value" => "The Queen", "@language" => "en"}
              ]
            }
          ]
        },
        "expand-0035" => {
          input: {
            "@context" => {
              "@vocab" => "http://example.com/vocab/",
              "@language" => "it",
              "label" => {
                "@container" => "@language"
              }
            },
            "@id" => "http://example.com/queen",
            "label" => {
              "en" => "The Queen",
              "de" => [ "Die Königin", "Ihre Majestät" ]
            },
            "http://example.com/vocab/label" => [
              "Il re",
              { "@value" => "The king", "@language" => "en" }
            ]
          },
          output: [
            {
              "@id" => "http://example.com/queen",
              "http://example.com/vocab/label" => [
                {"@value" => "Il re", "@language" => "it"},
                {"@value" => "The king", "@language" => "en"},
                {"@value" => "Die Königin", "@language" => "de"},
                {"@value" => "Ihre Majestät", "@language" => "de"},
                {"@value" => "The Queen", "@language" => "en"},
              ]
            }
          ]
        }
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "@container: @id" do
      {
        "Adds @id to object not having an @id" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "http://example.org/foo": {"label": "Object with @id <foo>"},
              "_:bar": {"label": "Object with @id _:bar"}
            }
          }),
          output: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with @id _:bar"}], "@id": "_:bar"},
              {"http://example/label": [{"@value": "Object with @id <foo>"}], "@id": "http://example.org/foo"}
            ]
          }])
        },
        "Retains @id in object already having an @id" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "http://example.org/foo": {"@id": "http://example.org/bar", "label": "Object with @id <foo>"},
              "_:bar": {"@id": "_:foo", "label": "Object with @id _:bar"}
            }
          }),
          output: %([{
            "http://example/idmap": [
              {"@id": "_:foo", "http://example/label": [{"@value": "Object with @id _:bar"}]},
              {"@id": "http://example.org/bar", "http://example/label": [{"@value": "Object with @id <foo>"}]}
            ]
          }])
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "@container: @type" do
      {
        "Adds @type to object not having an @type" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"label": "Object with @type <foo>"},
              "_:bar": {"label": "Object with @type _:bar"}
            }
          }),
          output: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type _:bar"}], "@type": ["_:bar"]},
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example.org/foo"]}
            ]
          }
        ])
        },
        "Prepends @type in object already having an @type" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"@type": "http://example.org/bar", "label": "Object with @type <foo>"},
              "_:bar": {"@type": "_:foo", "label": "Object with @type _:bar"}
            }
          }),
          output: %([{
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
          }])
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "scoped context" do
      {
        "adding new term" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "foo": {
              "bar": "baz"
            }
          }),
          output: %([
            {
              "http://example/foo": [{"http://example.org/bar": [{"@value": "baz"}]}]
            }
          ])
        },
        "overriding a term" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"bar": {"@type": "@id"}}},
              "bar": {"@type": "http://www.w3.org/2001/XMLSchema#string"}
            },
            "foo": {
              "bar": "http://example/baz"
            }
          }),
          output: %([
            {
              "http://example/foo": [{"http://example/bar": [{"@id": "http://example/baz"}]}]
            }
          ])
        },
        "property and value with different terms mapping to the same expanded property" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"Bar": {"@id": "bar"}}}
            },
            "foo": {
              "Bar": "baz"
            }
          }),
          output: %([
            {
              "http://example/foo": [{
                "http://example/bar": [
                  {"@value": "baz"}
                ]}
              ]
            }
          ])
        },
        "deep @context affects nested nodes" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"baz": {"@type": "@vocab"}}}
            },
            "foo": {
              "bar": {
                "baz": "buzz"
              }
            }
          }),
          output: %([
            {
              "http://example/foo": [{
                "http://example/bar": [{
                  "http://example/baz": [{"@id": "http://example/buzz"}]
                }]
              }]
            }
          ])
        },
        "scoped context layers on intemediate contexts" => {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "b": {"@context": {"c": "http://example.org/c"}}
            },
            "a": {
              "@context": {"@vocab": "http://example.com/"},
              "b": {
                "a": "A in example.com",
                "c": "C in example.org"
              },
              "c": "C in example.com"
            },
            "c": "C in example"
          }),
          output: %([{
            "http://example/a": [{
              "http://example.com/c": [{"@value": "C in example.com"}],
              "http://example/b": [{
                "http://example.com/a": [{"@value": "A in example.com"}],
                "http://example.org/c": [{"@value": "C in example.org"}]
              }]
            }],
            "http://example/c": [{"@value": "C in example"}]
          }])
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "@reverse" do
      {
        "expand-0037" => {
          input: %({
            "@context": {
              "name": "http://xmlns.com/foaf/0.1/name"
            },
            "@id": "http://example.com/people/markus",
            "name": "Markus Lanthaler",
            "@reverse": {
              "http://xmlns.com/foaf/0.1/knows": {
                "@id": "http://example.com/people/dave",
                "name": "Dave Longley"
              }
            }
          }),
          output: %([
            {
              "@id": "http://example.com/people/markus",
              "@reverse": {
                "http://xmlns.com/foaf/0.1/knows": [
                  {
                    "@id": "http://example.com/people/dave",
                    "http://xmlns.com/foaf/0.1/name": [
                      {
                        "@value": "Dave Longley"
                      }
                    ]
                  }
                ]
              },
              "http://xmlns.com/foaf/0.1/name": [
                {
                  "@value": "Markus Lanthaler"
                }
              ]
            }
          ])
        },
        "expand-0043" => {
          input: %({
            "@context": {
              "name": "http://xmlns.com/foaf/0.1/name",
              "isKnownBy": { "@reverse": "http://xmlns.com/foaf/0.1/knows" }
            },
            "@id": "http://example.com/people/markus",
            "name": "Markus Lanthaler",
            "@reverse": {
              "isKnownBy": [
                {
                  "@id": "http://example.com/people/dave",
                  "name": "Dave Longley"
                },
                {
                  "@id": "http://example.com/people/gregg",
                  "name": "Gregg Kellogg"
                }
              ]
            }
          }),
          output: %([
            {
              "@id": "http://example.com/people/markus",
              "http://xmlns.com/foaf/0.1/knows": [
                {
                  "@id": "http://example.com/people/dave",
                  "http://xmlns.com/foaf/0.1/name": [
                    {
                      "@value": "Dave Longley"
                    }
                  ]
                },
                {
                  "@id": "http://example.com/people/gregg",
                  "http://xmlns.com/foaf/0.1/name": [
                    {
                      "@value": "Gregg Kellogg"
                    }
                  ]
                }
              ],
              "http://xmlns.com/foaf/0.1/name": [
                {
                  "@value": "Markus Lanthaler"
                }
              ]
            }
          ])
        },
        "@reverse object with an @id property" => {
          input: %({
            "@id": "http://example/foo",
            "@reverse": {
              "@id": "http://example/bar"
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidReversePropertyMap,
        },
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end

    context "exceptions" do
      {
        "non-null @value and null @type" => {
          input: {"http://example.com/foo" => {"@value" => "foo", "@type" => nil}},
          exception: JSON::LD::JsonLdError::InvalidTypeValue
        },
        "non-null @value and null @language" => {
          input: {"http://example.com/foo" => {"@value" => "foo", "@language" => nil}},
          exception: JSON::LD::JsonLdError::InvalidLanguageTaggedString
        },
        "value with null language" => {
          input: {
            "@context" => {"@language" => "en"},
            "http://example.org/nolang" => {"@value" => "no language", "@language" => nil}
          },
          exception: JSON::LD::JsonLdError::InvalidLanguageTaggedString
        },
        "colliding keywords" => {
          input: %({
            "@context": {
              "id": "@id",
              "ID": "@id"
            },
            "id": "http://example/foo",
            "ID": "http://example/bar"
          }),
          exception: JSON::LD::JsonLdError::CollidingKeywords,
        }
      }.each do |title, params|
        it(title) {run_expand params}
      end
    end
  end

  def run_expand(params)
    input, output = params[:input], params[:output]
    input = ::JSON.parse(input) if input.is_a?(String)
    output = ::JSON.parse(output) if output.is_a?(String)
    pending params.fetch(:pending, "test implementation") unless input
    if params[:exception]
      expect {JSON::LD::API.expand(input)}.to raise_error(params[:exception])
    else
      jld = JSON::LD::API.expand(input, base: params[:base], logger: logger)
      expect(jld).to produce(output, logger)
    end
  end
end
