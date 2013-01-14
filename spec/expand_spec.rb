# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".expand" do
    {
      "empty doc" => {
        :input => {},
        :output => []
      },
      "coerced IRI" => {
        :input => {
          "@context" => {
            "a" => {"@id" => "http://example.com/a"},
            "b" => {"@id" => "http://example.com/b", "@type" => "@id"},
            "c" => {"@id" => "http://example.com/c"},
          },
          "@id" => "a",
          "b"   => "c"
        },
        :output => [{
          "@id" => "http://example.com/a",
          "http://example.com/b" => [{"@id" =>"http://example.com/c"}]
        }]
      },
      "coerced IRI in array" => {
        :input => {
          "@context" => {
            "a" => {"@id" => "http://example.com/a"},
            "b" => {"@id" => "http://example.com/b", "@type" => "@id"},
            "c" => {"@id" => "http://example.com/c"},
          },
          "@id" => "a",
          "b"   => ["c"]
        },
        :output => [{
          "@id" => "http://example.com/a",
          "http://example.com/b" => [{"@id" => "http://example.com/c"}]
        }]
      },
      "empty term" => {
        :input => {
          "@context" => {"" => "http://example.com/"},
          "@id" => "",
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :output => [{
          "@id" => "http://example.com/",
          "@type" => ["#{RDF::RDFS.Resource}"]
        }]
      },
      "@list coercion" => {
        :input => {
          "@context" => {
            "foo" => {"@id" => "http://example.com/foo", "@container" => "@list"}
          },
          "foo" => [{"@value" => "bar"}]
        },
        :output => [{
          "http://example.com/foo" => [{"@list" => [{"@value" => "bar"}]}]
        }]
      },
      "native values in list" => {
        :input => {
          "http://example.com/foo" => {"@list" => [1, 2]}
        },
        :output => [{
          "http://example.com/foo" => [{"@list" => [{"@value" => 1}, {"@value" => 2}]}]
        }]
      },
      "@graph" => {
        :input => {
          "@context" => {"ex" => "http://example.com/"},
          "@graph" => [
            {"ex:foo"  => {"@value" => "foo"}},
            {"ex:bar" => {"@value" => "bar"}}
          ]
        },
        :output => [
          {"http://example.com/foo" => [{"@value" => "foo"}]},
          {"http://example.com/bar" => [{"@value" => "bar"}]}
        ]
      },
      "@type with empty object" => {
        :input => {
          "@type" => {}
        },
        :output => [
          {"@type" => [{}]}
        ]
      },
      "@type with CURIE" => {
        :input => {
          "@context" => {"ex" => "http://example.com/"},
          "@type" => "ex:type"
        },
        :output => [
          {"@type" => ["http://example.com/type"]}
        ]
      },
      "@type with CURIE and muliple values" => {
        :input => {
          "@context" => {"ex" => "http://example.com/"},
          "@type" => ["ex:type1", "ex:type2"]
        },
        :output => [
          {"@type" => ["http://example.com/type1", "http://example.com/type2"]}
        ]
      },
    }.each_pair do |title, params|
      it title do
        jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
        jld.should produce(params[:output], @debug)
      end
    end

    context "with relative IRIs" do
      {
        "base" => {
          :input => {
            "@id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => [{
            "@id" => "http://example.org/",
            "@type" => ["#{RDF::RDFS.Resource}"]
          }]
        },
        "relative" => {
          :input => {
            "@id" => "a/b",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => [{
            "@id" => "http://example.org/a/b",
            "@type" => ["#{RDF::RDFS.Resource}"]
          }]
        },
        "hash" => {
          :input => {
            "@id" => "#a",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => [{
            "@id" => "http://example.org/#a",
            "@type" => ["#{RDF::RDFS.Resource}"]
          }]
        },
        "unmapped @id" => {
          :input => {
            "http://example.com/foo" => {"@id" => "bar"}
          },
          :output => [{
            "http://example.com/foo" => [{"@id" => "http://example.org/bar"}]
          }]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :base => "http://example.org/", :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "keyword aliasing" do
      {
        "@id" => {
          :input => {
            "@context" => {"id" => "@id"},
            "id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => [{
            "@id" => "",
            "@type" =>[ "#{RDF::RDFS.Resource}"]
          }]
        },
        "@type" => {
          :input => {
            "@context" => {"type" => "@type"},
            "type" => RDF::RDFS.Resource.to_s,
            "http://example.com/foo" => {"@value" => "bar", "type" => "http://example.com/baz"}
          },
          :output => [{
            "@type" => [RDF::RDFS.Resource.to_s],
            "http://example.com/foo" => [{"@value" => "bar", "@type" => "http://example.com/baz"}]
          }]
        },
        "@language" => {
          :input => {
            "@context" => {"language" => "@language"},
            "http://example.com/foo" => {"@value" => "bar", "language" => "baz"}
          },
          :output => [{
            "http://example.com/foo" => [{"@value" => "bar", "@language" => "baz"}]
          }]
        },
        "@value" => {
          :input => {
            "@context" => {"literal" => "@value"},
            "http://example.com/foo" => {"literal" => "bar"}
          },
          :output => [{
            "http://example.com/foo" => [{"@value" => "bar"}]
          }]
        },
        "@list" => {
          :input => {
            "@context" => {"list" => "@list"},
            "http://example.com/foo" => {"list" => ["bar"]}
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => [{"@value" => "bar"}]}]
          }]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "native types" do
      {
        "true" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => true
          },
          :output => [{
            "http://example.org/vocab#bool" => [{"@value" => true}]
          }]
        },
        "false" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => false
          },
          :output => [{
            "http://example.org/vocab#bool" => [{"@value" => false}]
          }]
        },
        "double" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double" => 1.23
          },
          :output => [{
            "http://example.org/vocab#double" => [{"@value" => 1.23}]
          }]
        },
        "double-zero" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double-zero" => 0.0e0
          },
          :output => [{
            "http://example.org/vocab#double-zero" => [{"@value" => 0.0e0}]
          }]
        },
        "integer" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:integer" => 123
          },
          :output => [{
            "http://example.org/vocab#integer" => [{"@value" => 123}]
          }]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "coerced typed values" do
      {
        "boolean" => {
          :input => {
            "@context" => {"foo" => {"@id" => "http://example.org/foo", "@type" => RDF::XSD.boolean.to_s}},
            "foo" => "true"
          },
          :output => [{
            "http://example.org/foo" => [{"@value" => "true", "@type" => RDF::XSD.boolean.to_s}]
          }]
        },
        "date" => {
          :input => {
            "@context" => {"foo" => {"@id" => "http://example.org/foo", "@type" => RDF::XSD.date.to_s}},
            "foo" => "2011-03-26"
          },
          :output => [{
            "http://example.org/foo" => [{"@value" => "2011-03-26", "@type" => RDF::XSD.date.to_s}]
          }]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "null" do
      {
        "value" => {
          :input => {
            "http://example.com/foo" => nil
          },
          :output => []
        },
        "@value" => {
          :input => {
            "http://example.com/foo" => {"@value" => nil}
          },
          :output => []
        },
        "@value and non-null @type" => {
          :input => {
            "http://example.com/foo" => {"@value" => nil, "@type" => "http://type"}
          },
          :output => []
        },
        "@value and non-null @language" => {
          :input => {
            "http://example.com/foo" => {"@value" => nil, "@language" => "en"}
          },
          :output => []
        },
        "non-null @value and null @type" => {
          :input => {
            "http://example.com/foo" => {"@value" => "foo", "@type" => nil}
          },
          :output => [{
            "http://example.com/foo" => [{"@value" => "foo"}]
          }]
        },
        "non-null @value and null @language" => {
          :input => {
            "http://example.com/foo" => {"@value" => "foo", "@language" => nil}
          },
          :output => [{
            "http://example.com/foo" => [{"@value" => "foo"}]
          }]
        },
        "array with null elements" => {
          :input => {
            "http://example.com/foo" => [nil]
          },
          :output => [{
            "http://example.com/foo" => []
          }]
        },
        "@set with null @value" => {
          :input => {
            "http://example.com/foo" => [
              {"@value" => nil, "@type" => "http://example.org/Type"}
            ]
          },
          :output => [{
            "http://example.com/foo" => []
          }]
        }
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "default language" do
      {
        "value with null language" => {
          :input => {
            "@context" => {"@language" => "en"},
            "http://example.org/nolang" => {"@value" => "no language", "@language" => nil}
          },
          :output => [{
            "http://example.org/nolang" => [{"@value" => "no language"}]
          }]
        },
        "value with coerced null language" => {
          :input => {
            "@context" => {
              "@language" => "en",
              "ex" => "http://example.org/vocab#",
              "ex:german" => { "@language" => "de" },
              "ex:nolang" => { "@language" => nil }
            },
            "ex:german" => "german",
            "ex:nolang" => "no language"
          },
          :output => [
            {
              "http://example.org/vocab#german" => [{"@value" => "german", "@language" => "de"}],
              "http://example.org/vocab#nolang" => [{"@value" => "no language"}]
            }
          ]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "default vocabulary" do
      {
        "property" => {
          :input => {
            "@context" => {"@vocab" => "http://example.com/"},
            "verb" => {"@value" => "foo"}
          },
          :output => [{
            "http://example.com/verb" => [{"@value" => "foo"}]
          }]
        },
        "datatype" => {
          :input => {
            "@context" => {"@vocab" => "http://example.com/"},
            "http://example.org/verb" => {"@value" => "foo", "@type" => "string"}
          },
          :output => [
            "http://example.org/verb" => [{"@value" => "foo", "@type" => "http://example.com/string"}]
          ]
        },
        "expand-0028" => {
          :input => {
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
          :output => [
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
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil,
            :base => "http://foo/bar/",
            :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "unmapped properties" do
      {
        "unmapped key" => {
          :input => {
            "foo" => "bar"
          },
          :output => []
        },
        "unmapped @type as datatype" => {
          :input => {
            "http://example.com/foo" => {"@value" => "bar", "@type" => "baz"}
          },
          :output => [{
            "http://example.com/foo" => [{"@value" => "bar"}]
          }]
        },
        "unknown keyword" => {
          :input => {
            "@foo" => "bar"
          },
          :output => []
        },
        "value" => {
          :input => {
            "@context" => {"ex" => {"@id" => "http://example.org/idrange", "@type" => "@id"}},
            "@id" => "http://example.org/Subj",
            "idrange" => "unmapped"
          },
          :output => []
        },
        "context reset" => {
          :input => {
            "@context" => {"ex" => "http://example.org/", "prop" => "ex:prop"},
            "@id" => "http://example.org/id1",
            "prop" => "prop",
            "ex:chain" => {
              "@context" => nil,
              "@id" => "http://example.org/id2",
              "prop" => "prop"
            }
          },
          :output => [{
            "@id" => "http://example.org/id1",
            "http://example.org/prop" => [{"@value" => "prop"}],
            "http://example.org/chain" => [{"@id" => "http://example.org/id2"}]
          }
        ]}
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "lists" do
      {
        "empty" => {
          :input => {
            "http://example.com/foo" => {"@list" => []}
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => []}]
          }]
        },
        "coerced empty" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@list"}},
            "http://example.com/foo" => []
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => []}]
          }]
        },
        "coerced single element" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@list"}},
            "http://example.com/foo" => [ "foo" ]
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => [{"@value" => "foo"}]}]
          }]
        },
        "coerced multiple elements" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@list"}},
            "http://example.com/foo" => [ "foo", "bar" ]
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => [ {"@value" => "foo"}, {"@value" => "bar"} ]}]
          }]
        },
        "explicit list with coerced @id values" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@type" => "@id"}},
            "http://example.com/foo" => {"@list" => ["http://foo", "http://bar"]}
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => [{"@id" => "http://foo"}, {"@id" => "http://bar"}]}]
          }]
        },
        "explicit list with coerced datatype values" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@type" => RDF::XSD.date.to_s}},
            "http://example.com/foo" => {"@list" => ["2012-04-12"]}
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => [{"@value" => "2012-04-12", "@type" => RDF::XSD.date.to_s}]}]
          }]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "sets" do
      {
        "empty" => {
          :input => {
            "http://example.com/foo" => {"@set" => []}
          },
          :output => [{
            "http://example.com/foo" => []
          }]
        },
        "coerced empty" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@set"}},
            "http://example.com/foo" => []
          },
          :output => [{
            "http://example.com/foo" => []
          }]
        },
        "coerced single element" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@set"}},
            "http://example.com/foo" => [ "foo" ]
          },
          :output => [{
            "http://example.com/foo" => [ {"@value" => "foo"} ]
          }]
        },
        "coerced multiple elements" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@set"}},
            "http://example.com/foo" => [ "foo", "bar" ]
          },
          :output => [{
            "http://example.com/foo" => [ {"@value" => "foo"}, {"@value" => "bar"} ]
          }]
        },
        "array containing set" => {
          :input => {
            "http://example.com/foo" => [{"@set" => []}]
          },
          :output => [{
            "http://example.com/foo" => []
          }]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "language maps" do
      {
        "simple map" => {
          :input => {
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
          :output => [
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
          :input => {
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
          :output => [
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
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "annotations" do
      {
        "string annotation" => {
          :input => {
            "@context" => {
              "container" => {
                "@id" => "http://example.com/container",
                "@container" => "@annotation"
              }
            },
            "@id" => "http://example.com/annotationsTest",
            "container" => {
              "en" => "The Queen",
              "de" => [ "Die Königin", "Ihre Majestät" ]
            }
          },
          :output => [
            {
              "@id" => "http://example.com/annotationsTest",
              "http://example.com/container" => [
                {"@value" => "Die Königin", "@annotation" => "de"},
                {"@value" => "Ihre Majestät", "@annotation" => "de"},
                {"@value" => "The Queen", "@annotation" => "en"}
              ]
            }
          ]
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "property generators" do
      {
        "expand-0038" => {
          :input => {
            "@context" => {
              "site" => "http://example.com/",
              "field_tags" => {
                "@id" => [ "site:vocab/field_tags", "http://schema.org/about" ]
              },
              "field_related" => {
                "@id" => [ "site:vocab/field_related", "http://schema.org/about" ]
              }
            },
            "@id" => "site:node/1",
            "field_tags" => [
              { "@id" => "site:term/this-is-a-tag" }
            ],
            "field_related" => [
              { "@id" => "site:node/this-is-related-news" }
            ]
          },
          :output => [{
             "@id" => "http://example.com/node/1",
             "http://example.com/vocab/field_related" => [{
                "@id" => "http://example.com/node/this-is-related-news"
             }],
             "http://schema.org/about" => [{
                "@id" => "http://example.com/node/this-is-related-news"
             }, {
                "@id" => "http://example.com/term/this-is-a-tag"
             }],
             "http://example.com/vocab/field_tags" => [{
                "@id" => "http://example.com/term/this-is-a-tag"
             }]
          }]
        },
        "generate bnodel ids" => {
          :input => {
            "@context" => {
              "site" => "http://example.com/",
              "field_tags" => {
                "@id" => [ "site:vocab/field_tags", "http://schema.org/about" ]
              }
            },
            "@id" => "site:node/1",
            "field_tags" => [
              { "@type" => "site:term/this-is-a-tag" },
              "foo"
            ]
          },
          :output => [{
             "@id" => "http://example.com/node/1",
             "http://schema.org/about" => [{
               "@id" => "_:t0",
               "@type" => ["http://example.com/term/this-is-a-tag"]
             }, {
               "@value" => "foo"
             }],
             "http://example.com/vocab/field_tags" => [{
               "@id" => "_:t0",
               "@type" => ["http://example.com/term/this-is-a-tag"]
             }, {
               "@value" => "foo"
             }]
          }]
        }
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "exceptions" do
      {
        "@list containing @list" => {
          :input => {
            "http://example.com/foo" => {"@list" => [{"@list" => ["baz"]}]}
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
        "@list containing @list (with coercion)" => {
          :input => {
            "@context" => {"foo" => {"@id" => "http://example.com/foo", "@container" => "@list"}},
            "foo" => [{"@list" => ["baz"]}]
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
        "coerced @list containing an array" => {
          :input => {
            "@context" => {"foo" => {"@id" => "http://example.com/foo", "@container" => "@list"}},
            "foo" => [["baz"]]
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
      }.each do |title, params|
        it title do
          #JSON::LD::API.expand(params[:input], nil, nil, :debug => @debug).should produce([], @debug)
          lambda {JSON::LD::API.expand(params[:input], nil, nil)}.should raise_error(params[:exception])
        end
      end
    end
  end
end
