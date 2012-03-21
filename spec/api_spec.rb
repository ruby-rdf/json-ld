# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".expand" do
    {
      "empty doc" => {
        :input => {},
        :output => {}
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
        :output => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => {"@id" =>"http://example.com/c"}
        }
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
        :output => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => [{"@id" => "http://example.com/c"}]
        }
      },
      "empty term" => {
        :input => {
          "@context" => {"" => "http://example.com/"},
          "@id" => "",
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :output => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        }
      },
    }.each_pair do |title, params|
      it title do
        jld = JSON::LD::API.expand(params[:input], nil, :debug => @debug)
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
          :output => {
            "@id" => "http://example.org/",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
        "relative" => {
          :input => {
            "@id" => "a/b",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => {
            "@id" => "http://example.org/a/b",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
        "hash" => {
          :input => {
            "@id" => "#a",
            "@type" => "#{RDF::RDFS.Resource}"
          },
          :output => {
            "@id" => "http://example.org/#a",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, :base_uri => "http://example.org/", :debug => @debug)
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
          :output => {
            "@id" => "",
            "@type" => "#{RDF::RDFS.Resource}"
          }
        },
        "@type" => {
          :input => {
            "@context" => {"type" => "@type"},
            "type" => RDF::RDFS.Resource.to_s,
            "foo" => {"@value" => "bar", "type" => "baz"}
          },
          :output => {
            "@type" => RDF::RDFS.Resource.to_s,
            "foo" => {"@value" => "bar", "@type" => "baz"}
          }
        },
        "@language" => {
          :input => {
            "@context" => {"language" => "@language"},
            "foo" => {"@value" => "bar", "language" => "baz"}
          },
          :output => {
            "foo" => {"@value" => "bar", "@language" => "baz"}
          }
        },
        "@value" => {
          :input => {
            "@context" => {"literal" => "@value"},
            "foo" => {"literal" => "bar"}
          },
          :output => {
            "foo" => {"@value" => "bar"}
          }
        },
        "@list" => {
          :input => {
            "@context" => {"list" => "@list"},
            "foo" => {"list" => ["bar"]}
          },
          :output => {
            "foo" => {"@list" => ["bar"]}
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, :debug => @debug)
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
          :output => {
            "http://example.org/vocab#bool" => {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}
          }
        },
        "false" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:bool" => false
          },
          :output => {
            "http://example.org/vocab#bool" => {"@value" => "false", "@type" => RDF::XSD.boolean.to_s}
          }
        },
        "double" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double" => 1.23
          },
          :output => {
            "http://example.org/vocab#double" => {"@value" => "1.230000e+00", "@type" => RDF::XSD.double.to_s}
          }
        },
        "double-zero" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:double-zero" => 0.0e0
          },
          :output => {
            "http://example.org/vocab#double-zero" => {"@value" => "0.000000e+00", "@type" => RDF::XSD.double.to_s}
          }
        },
        "integer" => {
          :input => {
            "@context" => {"e" => "http://example.org/vocab#"},
            "e:integer" => 123
          },
          :output => {
            "http://example.org/vocab#integer" => {"@value" => "123", "@type" => RDF::XSD.integer.to_s}
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.expand(params[:input], nil, :debug => @debug)
          jld.should produce(params[:output], @debug)
        end
      end
    end

  end
  
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
          "http://example.com/b" => {"@value" => "2012-01-04", "@type" => "xsd:date"}
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@type" => "xsd:date"}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@type" => "xsd:date"}},
          "b" => "2012-01-04"
        }
      },
      "@list coercion" => {
        :input => {
          "http://example.com/b" => {"@list" => ["c", "d"]}
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@list" => true}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@list" => true}},
          "b" => ["c", "d"]
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
    }.each_pair do |title, params|
      it title do
        jld = JSON::LD::API.compact(params[:input], params[:context], :debug => @debug)
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
            "foo" => {"@value" => "bar", "@type" => "baz"}
          },
          :context => {"type" => "@type"},
          :output => {
            "@context" => {"type" => "@type"},
            "type" => RDF::RDFS.Resource.to_s,
            "foo" => {"@value" => "bar", "type" => "baz"}
          }
        },
        "@language" => {
          :input => {
            "foo" => {"@value" => "bar", "@language" => "baz"}
          },
          :context => {"language" => "@language"},
          :output => {
            "@context" => {"language" => "@language"},
            "foo" => {"@value" => "bar", "language" => "baz"}
          }
        },
        "@value" => {
          :input => {
            "foo" => {"@value" => "bar", "@language" => "baz"}
          },
          :context => {"literal" => "@value"},
          :output => {
            "@context" => {"literal" => "@value"},
            "foo" => {"literal" => "bar", "@language" => "baz"}
          }
        },
        "@list" => {
          :input => {
            "foo" => {"@list" => ["bar"]}
          },
          :context => {"list" => "@list"},
          :output => {
            "@context" => {"list" => "@list"},
            "foo" => {"list" => ["bar"]}
          }
        },
      }.each do |title, params|
        it title do
          jld = JSON::LD::API.compact(params[:input], params[:context], :debug => @debug)
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
        jld = JSON::LD::API.compact(input, ctx, :debug => @debug, :validate => true)
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
        jld = JSON::LD::API.compact(input, ctx, :debug => @debug, :validate => true)
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
        JSON::LD::EvaluationContext.any_instance.stub(:open).with("http://example.com/context").and_yield(ctx)
        jld = JSON::LD::API.compact(input, "http://example.com/context", :debug => @debug, :validate => true)
        jld.should produce(expected, @debug)
      end
    end
  end
  
  describe ".frame", :pending => true do
  end
  
  describe ".normalize", :pending => true do
  end
  
  describe ".triples" do
    it "FIXME"
  end
  
  context "Test Files" do
    Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'test-files/*-input.*'))) do |filename|
      test = File.basename(filename).sub(/-input\..*$/, '')
      frame = filename.sub(/-input\..*$/, '-frame.json')
      framed = filename.sub(/-input\..*$/, '-framed.json')
      compacted = filename.sub(/-input\..*$/, '-compacted.json')
      context = filename.sub(/-input\..*$/, '-context.json')
      expanded = filename.sub(/-input\..*$/, '-expanded.json')
      automatic = filename.sub(/-input\..*$/, '-automatic.json')
      ttl = filename.sub(/-input\..*$/, '-rdf.ttl')
      
      context test do
        before(:all) do
        end

        it "compacts" do
          jld = JSON::LD::API.compact(File.open(filename), File.open(context), :debug => @debug)
          jld.should produce(JSON.load(File.open(compacted)), @debug)
        end if File.exist?(compacted) && File.exist?(context)
        
        it "expands" do
          jld = JSON::LD::API.expand(File.open(filename), (File.open(context) if context), :debug => @debug)
          jld.should produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(expanded)
        
        it "frame", :pending => true do
          jld = JSON::LD::API.frame(File.open(filename), File.open(frame), :debug => @debug)
          jld.should produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(framed) && File.exist?(frame)

        it "Turtle" do
          RDF::Graph.load(filename, :debug => @debug).should be_equivalent_graph(RDF::Graph.load(ttl), :trace => @debug)
        end if File.exist?(ttl)
      end
    end
  end
end
