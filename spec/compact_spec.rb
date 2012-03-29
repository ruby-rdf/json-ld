# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".compact" do
    {
      "prefix" => {
        :input => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => {"@id" => "http://example.com/c"}
        },
        :context => {"ex" => "http://example.com/"},
        :output => {
          "@context" => {"ex" => "http://example.com/"},
          "@id" => "ex:a",
          "ex:b" => {"@id" => "ex:c"}
        }
      },
      "term" => {
        :input => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => {"@id" => "http://example.com/c"}
        },
        :context => {"b" => "http://example.com/b"},
        :output => {
          "@context" => {"b" => "http://example.com/b"},
          "@id" => "http://example.com/a",
          "b" => {"@id" => "http://example.com/c"}
        }
      },
      "@id" => {
        :input => {"@id" => "http://example.org/test#example"},
        :context => {},
        :output => {"@id" => "http://example.org/test#example"}
      },
      "@id coercion" => {
        :input => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => "http://example.com/c"
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@type" => "@id"}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@type" => "@id"}},
          "@id" => "http://example.com/a",
          "b" => "http://example.com/c"
        }
      },
      "xsd:date coercion" => {
        :input => {
          "http://example.com/b" => {"@value" => "2012-01-04", "@type" => RDF::XSD.date.to_s}
        },
        :context => {
          "xsd" => RDF::XSD.to_s,
          "b" => {"@id" => "http://example.com/b", "@type" => "xsd:date"}
        },
        :output => {
          "@context" => {
            "xsd" => RDF::XSD.to_s,
            "b" => {"@id" => "http://example.com/b", "@type" => "xsd:date"}
          },
          "b" => "2012-01-04"
        }
      },
      "@list coercion" => {
        :input => {
          "http://example.com/b" => {"@list" => ["c", "d"]}
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@container" => "@list"}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@container" => "@list"}},
          "b" => ["c", "d"]
        }
      },
      "@set coercion" => {
        :input => {
          "http://example.com/b" => {"@set" => ["c"]}
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@container" => "@set"}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@container" => "@set"}},
          "b" => ["c"]
        }
      },
      "empty @set coercion" => {
        :input => {
          "http://example.com/b" => []
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@container" => "@set"}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@container" => "@set"}},
          "b" => []
        }
      },
      "empty term" => {
        :input => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :context => {"" => "http://example.com/"},
        :output => {
          "@context" => {"" => "http://example.com/"},
          "@id" => "",
          "@type" => "#{RDF::RDFS.Resource}"
        },
      },
      "@id with expanded @id" => {
        :input => {
          "@id" => {"@id" => "http://example.com/"},
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :context => {},
        :output => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        },
      },
      "@type with string @id" => {
        :input => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :context => {},
        :output => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        },
      },
      "@type with array @id" => {
        :input => {
          "@id" => "http://example.com/",
          "@type" => ["#{RDF::RDFS.Resource}"]
        },
        :context => {},
        :output => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        },
      },
      "@type with expanded @id" => {
        :input => {
          "@id" => "http://example.com/",
          "@type" => {"@id" => "#{RDF::RDFS.Resource}"}
        },
        :context => {},
        :output => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        },
      },
      "@graph" => {
        :input => [
          {"http://example.com/foo" => ["foo"]},
          {"http://example.com/bar" => ["bar"]}
        ],
        :context => {"ex" => "http://example.com/"},
        :output => {
          "@context" => {"ex" => "http://example.com/"},
          "@graph" => [
            {"ex:foo"  => "foo"},
            {"ex:bar" => "bar"}
          ]
        }
      },
    }.each_pair do |title, params|
      it title do
        jld = JSON::LD::API.compact(params[:input], params[:context], nil, :debug => @debug)
        jld.should produce(params[:output], @debug)
      end
    end

    context "keyword aliasing" do
      {
        "@id" => {
          :input => {
            "@id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :context => {"id" => "@id"},
          :output => {
            "@context" => {"id" => "@id"},
            "id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
        "@type" => {
          :input => {
            "@type" => {"@id" => RDF::RDFS.Resource.to_s},
            "http://example.org/foo" => {"@value" => "bar", "@type" => "http://example.com/type"}
          },
          :context => {"type" => "@type"},
          :output => {
            "@context" => {"type" => "@type"},
            "type" => RDF::RDFS.Resource.to_s,
            "http://example.org/foo" => {"@value" => "bar", "type" => "http://example.com/type"}
          }
        },
        "@language" => {
          :input => {
            "http://example.org/foo" => {"@value" => "bar", "@language" => "baz"}
          },
          :context => {"language" => "@language"},
          :output => {
            "@context" => {"language" => "@language"},
            "http://example.org/foo" => {"@value" => "bar", "language" => "baz"}
          }
        },
        "@value" => {
          :input => {
            "http://example.org/foo" => {"@value" => "bar", "@language" => "baz"}
          },
          :context => {"literal" => "@value"},
          :output => {
            "@context" => {"literal" => "@value"},
            "http://example.org/foo" => {"literal" => "bar", "@language" => "baz"}
          }
        },
        "@list" => {
          :input => {
            "http://example.org/foo" => {"@list" => ["bar"]}
          },
          :context => {"list" => "@list"},
          :output => {
            "@context" => {"list" => "@list"},
            "http://example.org/foo" => {"list" => ["bar"]}
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.compact(params[:input], params[:context], nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

    context "context as value" do
      it "includes the context in the output document" do
        ctx = {
          "foo" => "http://example.com/"
        }
        input = {
          "http://example.com/" => "bar"
        }
        expected = {
          "@context" => {
            "foo" => "http://example.com/"
          },
          "foo" => "bar"
        }
        jld = JSON::LD::API.compact(input, ctx, nil, :debug => @debug, :validate => true)
        jld.should produce(expected, @debug)
      end
      
      it "removes unused terms from the context", :pending => "Perhaps this will just go away" do
        ctx = {
          "foo" => "http://example.com/",
          "baz" => "http://example.org/"
        }
        input = {
          "http://example.com/" => "bar"
        }
        expected = {
          "@context" => {
            "foo" => "http://example.com/"
          },
          "foo" => "bar"
        }
        jld = JSON::LD::API.compact(input, ctx, nil, :debug => @debug, :validate => true)
        jld.should produce(expected, @debug)
      end
    end

    context "context as reference" do
      it "uses referenced context" do
        ctx = StringIO.new(%q({"@context": {"b": "http://example.com/b"}}))
        input = {
          "http://example.com/b" => "c"
        }
        expected = {
          "@context" => "http://example.com/context",
          "b" => "c"
        }
        RDF::Util::File.stub(:open_file).with("http://example.com/context").and_yield(ctx)
        jld = JSON::LD::API.compact(input, "http://example.com/context", nil, :debug => @debug, :validate => true)
        jld.should produce(expected, @debug)
      end
    end

    context "exceptions" do
      {
        "@list containing @list" => {
          :input => {
            "http://example.org/foo" => {"@list" => [{"@list" => ["baz"]}]}
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
        "@list containing @list (with coercion)" => {
          :input => {
            "@context" => {"http://example.org/foo" => {"@container" => "@list"}},
            "http://example.org/foo" => [{"@list" => ["baz"]}]
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
        "@list containing array" => {
          :input => {
            "http://example.org/foo" => {"@list" => [["baz"]]}
          },
          :exception => JSON::LD::ProcessingError::ListOfLists
        },
      }.each do |title, params|
        it title do
          lambda {JSON::LD::API.compact(params[:input], {}, nil)}.should raise_error(params[:exception])
        end
      end
    end
  end
end
