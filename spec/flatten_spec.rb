# coding: utf-8
require_relative 'spec_helper'

describe JSON::LD::API do
  let(:logger) {RDF::Spec.logger}

  describe ".flatten" do
    {
      "single object": {
        input: %({"@id": "http://example.com", "@type": "http://www.w3.org/2000/01/rdf-schema#Resource"}),
        output: %([
          {"@id": "http://example.com", "@type": ["http://www.w3.org/2000/01/rdf-schema#Resource"]}
        ])
      },
      "embedded object": {
        input: %({
          "@context": {
            "foaf": "http://xmlns.com/foaf/0.1/"
          },
          "@id": "http://greggkellogg.net/foaf",
          "@type": "http://xmlns.com/foaf/0.1/PersonalProfileDocument",
          "foaf:primaryTopic": [{
            "@id": "http://greggkellogg.net/foaf#me",
            "@type": "http://xmlns.com/foaf/0.1/Person"
          }]
        }),
        output: %([
          {
            "@id": "http://greggkellogg.net/foaf",
            "@type": ["http://xmlns.com/foaf/0.1/PersonalProfileDocument"],
            "http://xmlns.com/foaf/0.1/primaryTopic": [{"@id": "http://greggkellogg.net/foaf#me"}]
          },
          {
            "@id": "http://greggkellogg.net/foaf#me",
            "@type": ["http://xmlns.com/foaf/0.1/Person"]
          }
        ])
      },
      "embedded anon": {
        input: %({
          "@context": {
            "foaf": "http://xmlns.com/foaf/0.1/"
          },
          "@id": "http://greggkellogg.net/foaf",
          "@type": "foaf:PersonalProfileDocument",
          "foaf:primaryTopic": {
            "@type": "foaf:Person"
          }
        }),
        output: %([
          {
            "@id": "_:b0",
            "@type": ["http://xmlns.com/foaf/0.1/Person"]
          },
          {
            "@id": "http://greggkellogg.net/foaf",
            "@type": ["http://xmlns.com/foaf/0.1/PersonalProfileDocument"],
            "http://xmlns.com/foaf/0.1/primaryTopic": [{"@id": "_:b0"}]
          }
        ])
      },
      "reverse properties": {
        input: %([
          {
            "@id": "http://example.com/people/markus",
            "@reverse": {
              "http://xmlns.com/foaf/0.1/knows": [
                {
                  "@id": "http://example.com/people/dave"
                },
                {
                  "@id": "http://example.com/people/gregg"
                }
              ]
            },
            "http://xmlns.com/foaf/0.1/name": [ { "@value": "Markus Lanthaler" } ]
          }
        ]),
        output: %([
          {
            "@id": "http://example.com/people/dave",
            "http://xmlns.com/foaf/0.1/knows": [
              {
                "@id": "http://example.com/people/markus"
              }
            ]
          },
          {
            "@id": "http://example.com/people/gregg",
            "http://xmlns.com/foaf/0.1/knows": [
              {
                "@id": "http://example.com/people/markus"
              }
            ]
          },
          {
            "@id": "http://example.com/people/markus",
            "http://xmlns.com/foaf/0.1/name": [
              {
                "@value": "Markus Lanthaler"
              }
            ]
          }
        ])
      },
      "Simple named graph (Wikidata)": {
        input: %q({
          "@context": {
            "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
            "ex": "http://example.org/",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "ex:locatedIn": {"@type": "@id"},
            "ex:hasPopulaton": {"@type": "xsd:integer"},
            "ex:hasReference": {"@type": "@id"}
          },
          "@graph": [
            {
              "@id": "http://example.org/ParisFact1",
              "@type": "rdf:Graph",
              "@graph": {
                "@id": "http://example.org/location/Paris#this",
                "ex:locatedIn": "http://example.org/location/France#this"
              },
              "ex:hasReference": ["http://www.britannica.com/", "http://www.wikipedia.org/", "http://www.brockhaus.de/"]
            },
            {
              "@id": "http://example.org/ParisFact2",
              "@type": "rdf:Graph",
              "@graph": {
                "@id": "http://example.org/location/Paris#this",
                "ex:hasPopulation": 7000000
              },
              "ex:hasReference": "http://www.wikipedia.org/"
            }
          ]
        }),
        output: %q([{
          "@id": "http://example.org/ParisFact1",
          "@type": ["http://www.w3.org/1999/02/22-rdf-syntax-ns#Graph"],
          "http://example.org/hasReference": [
            {"@id": "http://www.britannica.com/"},
            {"@id": "http://www.wikipedia.org/"},
            {"@id": "http://www.brockhaus.de/"}
          ],
          "@graph": [{
              "@id": "http://example.org/location/Paris#this",
              "http://example.org/locatedIn": [{"@id": "http://example.org/location/France#this"}]
            }]
          }, {
            "@id": "http://example.org/ParisFact2",
            "@type": ["http://www.w3.org/1999/02/22-rdf-syntax-ns#Graph"],
            "http://example.org/hasReference": [{"@id": "http://www.wikipedia.org/"}],
            "@graph": [{
              "@id": "http://example.org/location/Paris#this",
              "http://example.org/hasPopulation": [{"@value": 7000000}]
            }]
          }]),
      },
      "Test Manifest (shortened)": {
        input: %q{
          {
            "@id": "",
            "http://example/sequence": {"@list": [
              {
                "@id": "#t0001",
                "http://example/name": "Keywords cannot be aliased to other keywords",
                "http://example/input": {"@id": "error-expand-0001-in.jsonld"}
              }
            ]}
          }
        },
        output: %q{
          [{
            "@id": "",
            "http://example/sequence": [{"@list": [{"@id": "#t0001"}]}]
          }, {
            "@id": "#t0001",
            "http://example/input": [{"@id": "error-expand-0001-in.jsonld"}],
            "http://example/name": [{"@value": "Keywords cannot be aliased to other keywords"}]
          }]
        },
      },
      "@reverse bnode issue (0045)": {
        input: %q{
          {
            "@context": {
              "foo": "http://example.org/foo",
              "bar": { "@reverse": "http://example.org/bar", "@type": "@id" }
            },
            "foo": "Foo",
            "bar": [ "http://example.org/origin", "_:b0" ]
          }
        },
        output: %q{
          [
            {
              "@id": "_:b0",
              "http://example.org/foo": [ { "@value": "Foo" } ]
            },
            {
              "@id": "_:b1",
              "http://example.org/bar": [ { "@id": "_:b0" } ]
            },
            {
              "@id": "http://example.org/origin",
              "http://example.org/bar": [ { "@id": "_:b0" } ]
            }
          ]
        }
      },
      "@list with embedded object": {
        input: %([{
          "http://example.com/foo": [{
            "@list": [{
              "@id": "http://example.com/baz",
              "http://example.com/bar": "buz"}
            ]}
          ]}
        ]),
        output: %([
          {
            "@id": "_:b0",
            "http://example.com/foo": [{
              "@list": [
                {
                  "@id": "http://example.com/baz"
                }
              ]
            }]
          },
          {
            "@id": "http://example.com/baz",
            "http://example.com/bar": [{"@value": "buz"}]
          }
        ])
      },
      "coerced @list containing an deep list": {
        input: %([{
          "http://example.com/foo": [{"@list": [{"@list": [{"@list": [{"@value": "baz"}]}]}]}]
        }]),
        output: %([{
          "@id": "_:b0",
          "http://example.com/foo": [{"@list": [{"@list": [{"@list": [{"@value": "baz"}]}]}]}]
        }]),
      },
      "@list containing empty @list": {
        input: %({
          "http://example.com/foo": {"@list": [{"@list": []}]}
        }),
        output: %([{
          "@id": "_:b0",
          "http://example.com/foo": [{"@list": [{"@list": []}]}]
        }])
      },
      "coerced @list containing mixed list values": {
        input: %({
          "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
          "foo": [
            [{"@id": "http://example/a", "@type": "http://example/Bar"}],
            {"@id": "http://example/b", "@type": "http://example/Baz"}]
        }),
        output: %([{
          "@id": "_:b0",
          "http://example.com/foo": [{"@list": [
            {"@list": [{"@id": "http://example/a"}]},
            {"@id": "http://example/b"}
          ]}]
        },
        {
          "@id": "http://example/a",
          "@type": [
            "http://example/Bar"
          ]
        },
        {
          "@id": "http://example/b",
          "@type": [
            "http://example/Baz"
          ]
        }])
      },
    }.each do |title, params|
      it(title) {run_flatten(params)}
    end

    context "@included" do
      {
        "Basic Included array": {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": "value",
            "@included": [{
              "prop": "value2"
            }]
          }),
          output: %([{
            "@id": "_:b0",
            "http://example.org/prop": [{"@value": "value"}]
          }, {
            "@id": "_:b1",
            "http://example.org/prop": [{"@value": "value2"}]
          }])
        },
        "Basic Included object": {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": "value",
            "@included": {
              "prop": "value2"
            }
          }),
          output: %([{
            "@id": "_:b0",
            "http://example.org/prop": [{"@value": "value"}]
          }, {
            "@id": "_:b1",
            "http://example.org/prop": [{"@value": "value2"}]
          }])
        },
        "Multiple properties mapping to @included are folded together": {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/",
              "included1": "@included",
              "included2": "@included"
            },
            "included1": {"prop": "value1"},
            "included2": {"prop": "value2"}
          }),
          output: %([{
            "@id": "_:b1",
            "http://example.org/prop": [{"@value": "value1"}]
          }, {
            "@id": "_:b2",
            "http://example.org/prop": [{"@value": "value2"}]
          }])
        },
        "Included containing @included": {
          input: %({
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
          output: %([{
            "@id": "_:b0",
            "http://example.org/prop": [{"@value": "value"}]
          }, {
            "@id": "_:b1",
            "http://example.org/prop": [{"@value": "value2"}]
          }, {
            "@id": "_:b2",
            "http://example.org/prop": [{"@value": "value3"}]
          }])
        },
        "Property value with @included": {
          input: %({
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
          output: %([{
            "@id": "_:b0",
            "http://example.org/prop": [
              {"@id": "_:b1"}
            ]
          }, {
            "@id": "_:b1",
            "@type": ["http://example.org/Foo"]
          }, {
            "@id": "_:b2",
            "@type": ["http://example.org/Bar"]
          }])
        },
        "json.api example": {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/vocab#",
              "@base": "http://example.org/base/",
              "id": "@id",
              "type": "@type",
              "data": "@nest",
              "attributes": "@nest",
              "links": "@nest",
              "relationships": "@nest",
              "included": "@included",
              "self": {"@type": "@id"},
              "related": {"@type": "@id"},
              "comments": {
                "@context": {
                  "data": null
                }
              }
            },
            "data": [{
              "type": "articles",
              "id": "1",
              "attributes": {
                "title": "JSON:API paints my bikeshed!"
              },
              "links": {
                "self": "http://example.com/articles/1"
              },
              "relationships": {
                "author": {
                  "links": {
                    "self": "http://example.com/articles/1/relationships/author",
                    "related": "http://example.com/articles/1/author"
                  },
                  "data": { "type": "people", "id": "9" }
                },
                "comments": {
                  "links": {
                    "self": "http://example.com/articles/1/relationships/comments",
                    "related": "http://example.com/articles/1/comments"
                  },
                  "data": [
                    { "type": "comments", "id": "5" },
                    { "type": "comments", "id": "12" }
                  ]
                }
              }
            }],
            "included": [{
              "type": "people",
              "id": "9",
              "attributes": {
                "first-name": "Dan",
                "last-name": "Gebhardt",
                "twitter": "dgeb"
              },
              "links": {
                "self": "http://example.com/people/9"
              }
            }, {
              "type": "comments",
              "id": "5",
              "attributes": {
                "body": "First!"
              },
              "relationships": {
                "author": {
                  "data": { "type": "people", "id": "2" }
                }
              },
              "links": {
                "self": "http://example.com/comments/5"
              }
            }, {
              "type": "comments",
              "id": "12",
              "attributes": {
                "body": "I like XML better"
              },
              "relationships": {
                "author": {
                  "data": { "type": "people", "id": "9" }
                }
              },
              "links": {
                "self": "http://example.com/comments/12"
              }
            }]
          }),
          output: %([{
            "@id": "_:b0",
            "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1/relationships/comments"}
            ],
            "http://example.org/vocab#related": [{"@id": "http://example.com/articles/1/comments"}]
          }, {
            "@id": "http://example.org/base/1",
            "@type": ["http://example.org/vocab#articles"],
            "http://example.org/vocab#title": [{"@value": "JSON:API paints my bikeshed!"}],
            "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1"}],
            "http://example.org/vocab#author": [{"@id": "http://example.org/base/9"}],
            "http://example.org/vocab#comments": [{"@id": "_:b0"}]
          }, {
            "@id": "http://example.org/base/12",
            "@type": ["http://example.org/vocab#comments"],
            "http://example.org/vocab#body": [{"@value": "I like XML better"}],
            "http://example.org/vocab#author": [{"@id": "http://example.org/base/9"}],
            "http://example.org/vocab#self": [{"@id": "http://example.com/comments/12"}]
          }, {
            "@id": "http://example.org/base/2",
            "@type": ["http://example.org/vocab#people"]
          }, {
            "@id": "http://example.org/base/5",
            "@type": ["http://example.org/vocab#comments"],
            "http://example.org/vocab#body": [{"@value": "First!"}
            ],
            "http://example.org/vocab#author": [{"@id": "http://example.org/base/2"}],
            "http://example.org/vocab#self": [{"@id": "http://example.com/comments/5"}]
          }, {
            "@id": "http://example.org/base/9",
            "@type": ["http://example.org/vocab#people"],
            "http://example.org/vocab#first-name": [{"@value": "Dan"}],
            "http://example.org/vocab#last-name": [{"@value": "Gebhardt"}],
            "http://example.org/vocab#twitter": [{"@value": "dgeb"}],
            "http://example.org/vocab#self": [
              {"@id": "http://example.com/people/9"},
              {"@id": "http://example.com/articles/1/relationships/author"}
            ],
            "http://example.org/vocab#related": [{"@id": "http://example.com/articles/1/author"}]
          }])
        },
      }.each do |title, params|
        it(title) {run_flatten(params)}
      end
    end
  end

  context "html" do
    {
      "Flattens embedded JSON-LD script element": {
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
          "@graph": [{"@id": "_:b0","foo": ["bar"]}]
        })
      },
      "Flattens first script element with extractAllScripts: false": {
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
          "@graph": [{"@id": "_:b0","foo": ["bar"]}]
        }),
        extractAllScripts: false
      },
      "Flattens targeted script element": {
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
            {"@id": "_:b0", "ex:foo": "foo"},
            {"@id": "_:b1", "ex:bar": "bar"}
          ]
        }),
        base: "http://example.org/doc#second"
      },
      "Flattens all script elements by default": {
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
            [
              {"http://example.com/foo": {"@value": "foo"}},
              {"http://example.com/bar": {"@value": "bar"}}
            ]
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
            {"@id": "_:b0", "foo": ["bar"]},
            {"@id": "_:b1", "ex:foo": "foo"},
            {"@id": "_:b2", "ex:bar": "bar"}
          ]
        })
      },
    }.each do |title, params|
      it(title) do
        params[:input] = StringIO.new(params[:input])
        params[:input].send(:define_singleton_method, :content_type) {"text/html"}
        run_flatten params.merge(validate: true)
      end
    end
  end

  context "JSON-LD*" do
    {
      "node object with @annotation property is ignored without rdfstar option": {
        input: %({
          "@id": "ex:bob",
          "ex:knows": {
            "@id": "ex:fred",
            "@annotation": {
              "ex:certainty": 0.8
            }
          }
        }),
        output: %([{
          "@id": "ex:bob",
          "ex:knows": [{"@id": "ex:fred"}]
        }])
      },
      "value object with @annotation property is ignored without rdfstar option": {
        input: %({
          "@id": "ex:bob",
          "ex:age": {
            "@value": 23,
            "@annotation": {
              "ex:certainty": 0.8
            }
          }
        }),
        output: %([{
          "@id": "ex:bob",
          "ex:age": [{"@value": 23}]
        }])
      },
    }.each do |title, params|
      it(title) {run_flatten params}
    end

    {
      "node with embedded subject having no @id": {
        input: %({
          "@id": {
            "ex:prop": "value"
          },
          "ex:prop": "value2"
        }),
        output: %([{
          "@id": {
            "ex:prop": [{"@value": "value"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with embedded subject having IRI @id": {
        input: %({
          "@id": {
            "@id": "ex:rei",
            "ex:prop": "value"
          },
          "ex:prop": "value2"
        }),
        output: %([{
          "@id": {
            "@id": "ex:rei",
            "ex:prop": [{"@value": "value"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with embedded subject having BNode @id": {
        input: %({
          "@id": {
            "@id": "_:rei",
            "ex:prop": "value"
          },
          "ex:prop": "value2"
        }),
        output: %([{
          "@id": {
            "@id": "_:b0",
            "ex:prop": [{"@value": "value"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with embedded subject having a type": {
        input: %({
          "@id": {
            "@id": "ex:rei",
            "@type": "ex:Type"
          },
          "ex:prop": "value2"
        }),
        output: %([{
          "@id": {
            "@id": "ex:rei",
            "@type": ["ex:Type"]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with embedded subject having an IRI value": {
        input: %({
          "@id": {
            "@id": "ex:rei",
            "ex:prop": {"@id": "ex:value"}
          },
          "ex:prop": "value2"
        }),
        output: %([{
          "@id": {
            "@id": "ex:rei",
            "ex:prop": [{"@id": "ex:value"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with embedded subject having an BNode value": {
        input: %({
          "@id": {
            "@id": "ex:rei",
            "ex:prop": {"@id": "_:value"}
          },
          "ex:prop": "value2"
        }),
        output: %([{
          "@id": {
            "@id": "ex:rei",
            "ex:prop": [{"@id": "_:b0"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with recursive embedded subject": {
        input: %({
          "@id": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": "value3"
            },
            "ex:prop": "value"
          },
          "ex:prop": "value2"
        }),
        output: %([{
          "@id": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@value": "value3"}]
            },
            "ex:prop": [{"@value": "value"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with embedded object": {
        input: %({
          "@id": "ex:subj",
          "ex:value": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": "value"
            }
          }
        }),
        output: %([{
          "@id": "ex:subj",
          "ex:value": [{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@value": "value"}]
            }
          }]
        }])
      },
      "node with embedded object having properties": {
        input: %({
          "@id": "ex:subj",
          "ex:value": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }
        }),
        output: %([{
          "@id": "ex:subj",
          "ex:value": [{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@value": "value"}]
            }
          }]
        }, {
          "@id": {
            "@id": "ex:rei",
            "ex:prop": [{"@value": "value"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with recursive embedded object": {
        input: %({
          "@id": "ex:subj",
          "ex:value": {
            "@id": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": "value3"
              },
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }
        }),
        output: %([{
          "@id": "ex:subj",
          "ex:value": [{
            "@id": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": [{"@value": "value3"}]
              },
              "ex:prop":[{"@value": "value"}]
            }
          }]
        }, {
          "@id": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@value": "value3"}]
            },
            "ex:prop":[{"@value": "value"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }])
      },
      "node with @annotation property on value object": {
        input: %({
          "@id": "ex:bob",
          "ex:age": {
            "@value": 23,
            "@annotation": {"ex:certainty": 0.8}
          }
        }),
        output: %([{
          "@id": "ex:bob",
          "ex:age": [{"@value": 23}]
        }, {
          "@id": {
            "@id": "ex:bob",
            "ex:age": [{"@value": 23}]
          },
          "ex:certainty": [{"@value": 0.8}]
        }])
      },
      "node with @annotation property on node object": {
        input: %({
          "@id": "ex:bob",
          "ex:name": "Bob",
          "ex:knows": {
            "@id": "ex:fred",
            "ex:name": "Fred",
            "@annotation": {"ex:certainty": 0.8}
          }
        }),
        output: %([{
          "@id": "ex:bob",
          "ex:name": [{"@value": "Bob"}],
          "ex:knows": [{"@id": "ex:fred"}]
        }, {
          "@id": "ex:fred",
          "ex:name": [{"@value": "Fred"}]
        }, {
          "@id": {
            "@id": "ex:bob",
            "ex:knows": [{"@id": "ex:fred"}]
          },
          "ex:certainty": [{"@value": 0.8}]
        }])
      },
      "node with @annotation property multiple values": {
        input: %({
          "@id": "ex:bob",
          "ex:name": "Bob",
          "ex:knows": {
            "@id": "ex:fred",
            "ex:name": "Fred",
            "@annotation": [{
              "ex:certainty": 0.8
            }, {
              "ex:source": {"@id": "http://example.org/"}
            }]
          }
        }),
        output: %([{
          "@id": "ex:bob",
          "ex:name": [{"@value": "Bob"}],
          "ex:knows": [{"@id": "ex:fred"}]
        }, {
          "@id": "ex:fred",
          "ex:name": [{"@value": "Fred"}]
        }, {
          "@id": {
            "@id": "ex:bob",
            "ex:knows": [{"@id": "ex:fred"}]
          },
          "ex:certainty": [{"@value": 0.8}],
          "ex:source": [{"@id": "http://example.org/"}]
        }])
      },
      "node with @annotation property on embedded subject": {
        input: %({
          "@id": {
            "@id": "ex:rei",
            "ex:prop": {"@id": "_:value"}
          },
          "ex:prop": {
            "@value": "value2",
            "@annotation": {"ex:certainty": 0.8}
          }
        }),
        output: %([{
          "@id": {
            "@id": "ex:rei",
            "ex:prop": [{"@id": "_:b0"}]
          },
          "ex:prop": [{"@value": "value2"}]
        }, {
          "@id": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@id": "_:b0"}]
            },
            "ex:prop": [{"@value": "value2"}]
          },
          "ex:certainty": [{"@value": 0.8}]
        }])
      },
      "node with @annotation property on embedded object": {
        input: %({
          "@id": "ex:subj",
          "ex:value": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": "value"
            },
            "@annotation": {"ex:certainty": 0.8}
          }
        }),
        output: %([{
          "@id": "ex:subj",
          "ex:value": [{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@value": "value"}]
            }
          }]
        }, {
          "@id": {
            "@id": "ex:subj",
            "ex:value": [{
              "@id": {
                "@id": "ex:rei",
                "ex:prop": [{"@value": "value"}]
              }
            }]
          },
          "ex:certainty": [{"@value": 0.8}]
        }])
      },
      "embedded node used as subject in reverse relationship": {
        input: %({
          "@context": {
            "rel": {"@reverse": "ex:rel"}
          },
          "@id": {
            "@id": "ex:rei",
            "ex:prop": {"@id": "ex:value"}
          },
          "rel": {"@id": "ex:value2"}
        }),
        output: %([{
          "@id": "ex:value2",
          "ex:rel": [{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@id": "ex:value"}]
            }
          }]
        }])
      },
      "embedded node used as object in reverse relationship": {
        input: %({
          "@context": {
            "rel": {"@reverse": "ex:rel"}
          },
          "@id": "ex:subj",
          "rel": {
            "@id": {
              "@id": "ex:rei",
              "ex:prop": {"@id": "ex:value"}
            },
            "ex:prop": {"@id": "ex:value2"}
          }
        }),
        output: %([{
          "@id": {
            "@id": "ex:rei",
            "ex:prop": [{"@id": "ex:value"}]
          },
          "ex:rel": [{"@id": "ex:subj"}],
          "ex:prop": [{"@id": "ex:value2"}]
        }
      ])
      },
      "node with @annotation property on node object with reverse relationship": {
        input: %({
          "@context": {
            "knownBy": {"@reverse": "ex:knows"}
          },
          "@id": "ex:bob",
          "ex:name": "Bob",
          "knownBy": {
            "@id": "ex:fred",
            "ex:name": "Fred",
            "@annotation": {"ex:certainty": 0.8}
          }
        }),
        output: %([{
          "@id": "ex:bob",
          "ex:name": [{"@value": "Bob"}]
        }, {
          "@id": "ex:fred",
          "ex:name": [{"@value": "Fred"}],
          "ex:knows": [{"@id": "ex:bob"}]
        }, {
          "@id": {
            "@id": "ex:fred",
            "ex:knows": [{"@id": "ex:bob"}]
          },
          "ex:certainty": [{"@value": 0.8}]
        }])
      },
      "reverse relationship inside annotation": {
        input: %({
          "@context": {
            "claims": {"@reverse": "ex:claims", "@type": "@id"}
          },
          "@id": "ex:bob",
          "ex:knows": {
            "@id": "ex:jane",
            "@annotation": {
              "ex:certainty": 0.8,
              "claims": "ex:sue"
            }
          }
        }),
        output: %([{
          "@id": "ex:bob",
          "ex:knows": [{"@id": "ex:jane"}]
        }, {
          "@id": {
            "@id": "ex:bob",
            "ex:knows": [{"@id": "ex:jane"}]
          },
          "ex:certainty": [{"@value": 0.8}]
        }, {
          "@id": "ex:sue",
          "ex:claims": [{
            "@id": {
              "@id": "ex:bob",
              "ex:knows": [{"@id": "ex:jane"}]
            }
          }]
        }])
      },
      "embedded node with annotation on value object": {
        input: %({
          "@context": {
            "@base": "http://example.org/",
            "@vocab": "http://example.org/",
            "claims": {"@type": "@id"}
          },
          "@id": {
            "@id": "bob",
            "knows": {"@id": "alice"}
          },
          "certainty": {
            "@value": 0.8,
            "@annotation": {"claims": "ted"}
          }
        }),
        output: %([{
          "@id": {
            "@id": "http://example.org/bob",
            "http://example.org/knows": [{"@id": "http://example.org/alice"}]
          },
          "http://example.org/certainty": [{"@value": 0.8}]
        }, {
          "@id": {
            "@id": {
              "@id": "http://example.org/bob",
              "http://example.org/knows": [{"@id": "http://example.org/alice"}]
            },
            "http://example.org/certainty": [{"@value": 0.8}]
          },
          "http://example.org/claims": [{"@id": "http://example.org/ted"}]
        }])
      }
    }.each do |title, params|
      it(title) {run_flatten params.merge(rdfstar: true)}
    end
  end

  def run_flatten(params)
    input, output, context = params[:input], params[:output], params[:context]
    input = ::JSON.parse(input) if input.is_a?(String)
    output = ::JSON.parse(output) if output.is_a?(String)
    context = ::JSON.parse(context) if context.is_a?(String)
    params[:base] ||= nil
    pending params.fetch(:pending, "test implementation") unless input
    if params[:exception]
      expect {JSON::LD::API.flatten(input, context, logger: logger, **params)}.to raise_error(params[:exception])
    else
      jld = nil
      if params[:write]
        expect{jld = JSON::LD::API.flatten(input, context, logger: logger, **params)}.to write(params[:write]).to(:error)
      else
        expect{jld = JSON::LD::API.flatten(input, context, logger: logger, **params)}.not_to write.to(:error)
      end
      expect(jld).to produce_jsonld(output, logger)
    end
  end
end
