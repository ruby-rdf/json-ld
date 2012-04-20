# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".expand" do
    {
      "empty doc" => {
        :input => {},
        :output => [{}]
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
          "foo" => ["bar"]
        },
        :output => [{
          "http://example.com/foo" => [{"@list" => ["bar"]}]
        }]
      },
      "@graph" => {
        :input => {
          "@context" => {"ex" => "http://example.com/"},
          "@graph" => [
            {"ex:foo"  => "foo"},
            {"ex:bar" => "bar"}
          ]
        },
        :output => [
          {"http://example.com/foo" => ["foo"]},
          {"http://example.com/bar" => ["bar"]}
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
            "http://example.com/foo" => ["bar"]
          }]
        },
        "@list" => {
          :input => {
            "@context" => {"list" => "@list"},
            "http://example.com/foo" => {"list" => ["bar"]}
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => ["bar"]}]
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
            "http://example.org/vocab#bool" => [true]
          }]
        },
        "false" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => false
          },
          :output => [{
            "http://example.org/vocab#bool" => [false]
          }]
        },
        "double" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double" => 1.23
          },
          :output => [{
            "http://example.org/vocab#double" => [1.23]
          }]
        },
        "double-zero" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double-zero" => 0.0e0
          },
          :output => [{
            "http://example.org/vocab#double-zero" => [0.0e0]
          }]
        },
        "integer" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:integer" => 123
          },
          :output => [{
            "http://example.org/vocab#integer" => [123]
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
          :output => [{
          }]
        },
        "@value" => {
          :input => {
            "http://example.com/foo" => {"@value" => nil}
          },
          :output => [{
          }]
        },
        "@value and non-null @type" => {
          :input => {
            "http://example.com/foo" => {"@value" => nil, "@type" => "http://type"}
          },
          :output => [{
          }]
        },
        "@value and non-null @language" => {
          :input => {
            "http://example.com/foo" => {"@value" => nil, "@language" => "en"}
          },
          :output => [{
          }]
        },
        "non-null @value and null @type" => {
          :input => {
            "http://example.com/foo" => {"@value" => "foo", "@type" => nil}
          },
          :output => [{
            "http://example.com/foo" => ["foo"]
          }]
        },
        "non-null @value and null @language" => {
          :input => {
            "http://example.com/foo" => {"@value" => "foo", "@language" => nil}
          },
          :output => [{
            "http://example.com/foo" => ["foo"]
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
            "http://example.org/nolang" => ["no language"]
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
              "http://example.org/vocab#nolang" => ["no language"]
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

    context "unmapped properties" do
      {
        "unmapped key" => {
          :input => {
            "foo" => "bar"
          },
          :output => [{
          }]
        },
        "unmapped @type as datatype" => {
          :input => {
            "http://example.com/foo" => {"@value" => "bar", "@type" => "baz"}
          },
          :output => [{
            "http://example.com/foo" => ["bar"]
          }]
        },
        "unknown keyword" => {
          :input => {
            "@foo" => "bar"
          },
          :output => [{
            "@foo" => ["bar"]
          }]
        },
        "value" => {
          :input => {
            "@context" => {"ex" => {"@id" => "http://example.org/idrange", "@type" => "@id"}},
            "@id" => "http://example.org/Subj",
            "idrange" => "unmapped"
          },
          :output => [{
            "@id" => "http://example.org/Subj",
          }]
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
            "http://example.org/prop" => ["prop"],
            "http://example.org/chain" => [{
              "@id" => "http://example.org/id2",
            }]
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
            "http://example.com/foo" => [{"@list" => [ "foo" ]}]
          }]
        },
        "coerced multiple elements" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@list"}},
            "http://example.com/foo" => [ "foo", "bar" ]
          },
          :output => [{
            "http://example.com/foo" => [{"@list" => [ "foo", "bar" ]}]
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
            "http://example.com/foo" => [ "foo" ]
          }]
        },
        "coerced multiple elements" => {
          :input => {
            "@context" => {"http://example.com/foo" => {"@container" => "@set"}},
            "http://example.com/foo" => [ "foo", "bar" ]
          },
          :output => [{
            "http://example.com/foo" => [ "foo", "bar" ]
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
