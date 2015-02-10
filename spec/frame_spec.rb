# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".frame" do
    {
      "frame with @type matches subject with @type" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1"
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "@type" => "ex:Type2"
          },
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1"
          }]
        }
      },
      "implicitly includes unframed properties" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1"
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }]
        }
      },
      "explicitly excludes unframed properties" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "@explicit" => true,
          "@type" => "ex:Type1"
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1"
          }]
        }
      },
      "explicitly includes unframed properties" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "@explicit" => false,
          "@type" => "ex:Type1"
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }]
        }
      },
      "frame without @type matches only subjects containing listed properties (duck typing)" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "ex:prop1" => {},
          "ex:prop2" => {}
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "ex:prop1" => "Property 1"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "ex:prop2" => "Property 2"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub3",
            "ex:prop1" => "Property 1",
            "ex:prop2" => "Property 2"
          },
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub3",
            "ex:prop1" => "Property 1",
            "ex:prop2" => "Property 2"
          }]
        }
      },
      "embed matched frames" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1",
          "ex:includes" => {
            "@type" => "ex:Type2"
          }
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:includes" => {"@id" => "ex:Sub2"}
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "@type" => "ex:Type2",
            "ex:includes" => {"@id" => "ex:Sub1"}
          },
        ],
        output:{
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:includes" => {
              "@id" => "ex:Sub2",
              "@type" => "ex:Type2",
              "ex:includes" => {"@id" => "ex:Sub1"}
            }
          }]
        }
      },
      "multiple matches" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1"
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "@type" => "ex:Type1"
          },
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [
              {
                "@id" => "ex:Sub1",
                "@type" => "ex:Type1"
              },
              {
                "@id" => "ex:Sub2",
                "@type" => "ex:Type1"
              }
            ]
          }
      },
      "non-existent framed properties create null property" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1",
          "ex:null" => []
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"},
            "ex:null" => nil
          }]
        }
      },
      "non-existent framed properties create default property" => {
        frame: {
          "@context" => {"ex" => "http://example.org/", "ex:null" => {"@container" => "@set"}},
          "@type" => "ex:Type1",
          "ex:null" => [{"@default" => "foo"}]
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        output: {
          "@context" => {"ex" => "http://example.org/", "ex:null" => {"@container" => "@set"}},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"},
            "ex:null" => ["foo"]
          }]
        }
      },
      "mixed content" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "ex:mixed" => {"@embed" => false}
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "ex:mixed" => [
              {"@id" => "ex:Sub2"},
              "literal1"
            ]
          }
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "ex:mixed" => [
              {"@id" => "ex:Sub2"},
              "literal1"
            ]
          }]
        }
      },
      "no embedding" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "ex:embed" => {"@embed" => false}
        },
        input: [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "ex:embed" => {
              "@id" => "ex:Sub2",
              "ex:prop" => "property"
            }
          }
        ],
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "ex:embed" =>  {"@id" => "ex:Sub2"}
          }]
        }
      },
      "mixed list" => {
        frame: {
          "@context" => {"ex" => "http://example.org/"},
          "ex:mixedlist" => {}
        },
        input: {
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1",
          "ex:mixedlist" => {"@list" => [
            {
              "@id" => "ex:Sub2",
              "@type" => "ex:Type2"
            },
            "literal1"
          ]}
        },
        output: {
          "@context" => {"ex" => "http://example.org/"},
          "@graph" => [{
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:mixedlist" => {"@list" => [
              {
                "@id" => "ex:Sub2",
                "@type" => "ex:Type2"
              },
              "literal1"
            ]}
          }]
        }
      },
      "presentation example" => {
        frame: {
          "@context" => {
            "primaryTopic" => {"@id" => "http://xmlns.com/foaf/0.1/primaryTopic","@type" => "@id"},
            "sameAs" => {"@id" => "http://www.w3.org/2002/07/owl#sameAs","@type" => "@id"},
          },
          "primaryTopic" => {
            "@type" => "http://dbpedia.org/class/yago/Buzzwords",
            "sameAs" => {}
          }
        },
        input: [
          {
            "@id" => "http://en.wikipedia.org/wiki/Linked_Data",
            "http://xmlns.com/foaf/0.1/primaryTopic" => [{"@id" => "http://dbpedia.org/resource/Linked_Data"}]
          },
          {
            "@id" => "http://www4.wiwiss.fu-berlin.de/flickrwrappr/photos/Linked_Data",
            "http://www.w3.org/2002/07/owl#sameAs" => [{"@id" => "http://dbpedia.org/resource/Linked_Data"}]
          },
          {
            "@id" => "http://dbpedia.org/resource/Linked_Data",
            "@type" => ["http://dbpedia.org/class/yago/Buzzwords"],
            "http://www.w3.org/2002/07/owl#sameAs" => [{"@id" => "http://rdf.freebase.com/ns/m/02r2kb1"}]
          },
          {
            "@id" => "http://mpii.de/yago/resource/Linked_Data",
            "http://www.w3.org/2002/07/owl#sameAs" => [{"@id" => "http://dbpedia.org/resource/Linked_Data"}]
          }
        ],
        output: {
          "@context" => {
            "primaryTopic" => {
              "@id" => "http://xmlns.com/foaf/0.1/primaryTopic",
              "@type" => "@id"
            },
            "sameAs" => {
              "@id" => "http://www.w3.org/2002/07/owl#sameAs",
              "@type" => "@id"
            }
          },
          "@graph" => [
            {
              "@id" => "http://en.wikipedia.org/wiki/Linked_Data",
              "primaryTopic" => {
                "@id" => "http://dbpedia.org/resource/Linked_Data",
                "@type" => "http://dbpedia.org/class/yago/Buzzwords",
                "sameAs" => "http://rdf.freebase.com/ns/m/02r2kb1"
              }
            }
          ]
        }
      },
      "microdata manifest" => {
        frame: {
          "@context" => {
            "xsd" => "http://www.w3.org/2001/XMLSchema#",
            "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
            "mf" => "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq" => "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
    
            "comment" => "rdfs:comment",
            "entries" => {"@id" => "mf:entries", "@container" => "@list"},
            "name" => "mf:name",
            "action" => "mf:action",
            "data" => {"@id" => "mq:data", "@type" => "@id"},
            "query" => {"@id" => "mq:query", "@type" => "@id"},
            "result" => {"@id" => "mf:result", "@type" => "xsd:boolean"}
          },
          "@type" => "mf:Manifest",
          "entries" => [{
            "@type" => "mf:ManifestEntry",
            "action" => {
              "@type" => "mq:QueryTest"
            }
          }]
        },
        input: {
          "@context" => {
            "md" => "http://www.w3.org/ns/md#",
            "mf" => "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq" => "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "rdfs" => "http://www.w3.org/2000/01/rdf-schema#"
          },
          "@graph" => [
            {
              "@id" => "_:manifest",
              "@type" => "mf:Manifest",
              "mf:entries" => {"@list" => [
                {"@id" => "_:entry"}
              ]},
              "rdfs:comment" => "Positive processor tests"
            },
            {
              "@id" => "_:entry",
              "@type" => "mf:ManifestEntry",
              "mf:action" => {"@id" => "_:query"},
              "mf:name" => "Test 0001",
              "mf:result" => "true",
              "rdfs:comment" => "Item with no itemtype and literal itemprop"
            },
            {
              "@id" => "_:query",
              "@type" => "mq:QueryTest",
              "mq:data" => {
                "@id" => "http://www.w3.org/TR/microdata-rdf/tests/0001.html"
              },
              "mq:query" => {
                "@id" => "http://www.w3.org/TR/microdata-rdf/tests/0001.ttl"
              }
            }
          ]
        },
        output: {
          "@context" => {
            "xsd" => "http://www.w3.org/2001/XMLSchema#",
            "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
            "mf" => "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq" => "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "comment" => "rdfs:comment",
            "entries" => {
              "@id" => "mf:entries",
              "@container" => "@list"
            },
            "name" => "mf:name",
            "action" => "mf:action",
            "data" => {
              "@id" => "mq:data",
              "@type" => "@id"
            },
            "query" => {
              "@id" => "mq:query",
              "@type" => "@id"
            },
            "result" => {
              "@id" => "mf:result",
              "@type" => "xsd:boolean"
            }
          },
          "@graph" => [
            {
              "@id" => "_:b0",
              "@type" => "mf:Manifest",
              "comment" => "Positive processor tests",
              "entries" => [
                {
                  "@id" => "_:b1",
                  "@type" => "mf:ManifestEntry",
                  "action" => {
                    "@id" => "_:b2",
                    "@type" => "mq:QueryTest",
                    "data" => "http://www.w3.org/TR/microdata-rdf/tests/0001.html",
                    "query" => "http://www.w3.org/TR/microdata-rdf/tests/0001.ttl"
                  },
                  "comment" => "Item with no itemtype and literal itemprop",
                  "mf:result" => "true",
                  "name" => "Test 0001"
                }
              ]
            }
          ]
        }
      }
    }.each do |title, params|
      it title do
        @debug = []
        begin
          jld = JSON::LD::API.frame(params[:input], params[:frame], debug: @debug)
          expect(jld).to produce(params[:output], @debug)
        rescue JSON::LD::JsonLdError, JSON::LD::JsonLdError, JSON::LD::InvalidFrame => e
          fail("#{e.class}: #{e.message}\n" +
            "#{@debug.join("\n")}\n" +
            "Backtrace:\n#{e.backtrace.join("\n")}")
        end
      end
    end

    describe "@reverse", skip:true do
      {
        "embed matched frames with @reverse" => {
          frame: {
            "@context" => {"ex" => "http://example.org/"},
            "@type" => "ex:Type1",
            "@reverse" => {
              "ex:includes" => {}
            }
          },
          input: [
            {
              "@context" => {"ex" => "http://example.org/"},
              "@id" => "ex:Sub1",
              "@type" => "ex:Type1"
            },
            {
              "@context" => {"ex" => "http://example.org/"},
              "@id" => "ex:Sub2",
              "@type" => "ex:Type2",
              "ex:includes" => {"@id" => "ex:Sub1"}
            },
          ],
          output:{
            "@context" => {"ex" => "http://example.org/"},
            "@graph" => [{
              "@id" => "ex:Sub1",
              "@type" => "ex:Type1",
              "@reverse" => {
                "ex:includes" => {
                  "@id" => "ex:Sub2",
                  "@type" => "ex:Type2",
                  "ex:includes" => {"@id" => "ex:Sub1"}
                }
              }
            }]
          }
        },
      }.each do |title, params|
        it title do
          @debug = []
          begin
            jld = JSON::LD::API.frame(params[:input], params[:frame], debug: @debug)
            expect(jld).to produce(params[:output], @debug)
          rescue JSON::LD::JsonLdError, JSON::LD::JsonLdError, JSON::LD::InvalidFrame => e
            fail("#{e.class}: #{e.message}\n" +
              "#{@debug.join("\n")}\n" +
              "Backtrace:\n#{e.backtrace.join("\n")}")
          end
        end
      end
    end
  end
end
