# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API, :pending => true do
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
            "a" => {"@iri" => "http://example.com/a"},
            "b" => {"@iri" => "http://example.com/b", "@datatype" => "@iri"},
            "c" => {"@iri" => "http://example.com/c"},
          },
          "@subject" => "a",
          "b"        => "c"
        },
        :output => {
          "@subject" => "http://example.com/a",
          "http://example.com/b" => "http://example.com/c"
        }
      },
      "coerced IRI in array" => {
        :input => {
          "@context" => {
            "a" => {"@iri" => "http://example.com/a"},
            "b" => {"@iri" => "http://example.com/b", "@datatype" => "@iri"},
            "c" => {"@iri" => "http://example.com/c"},
          },
          "@subject" => "a",
          "b"        => "c"
        },
        :output => {
          "@subject" => "http://example.com/a",
          "http://example.com/b" => "http://example.com/c"
        }
      },
    }.each_pair do |title, params|
      it title do
        JSON::LD::API.expand(params[:input], :debug => @debug).should produce(params[:output], @debug)
      end
    end
  end
  
  describe ".compact" do
    {
      "prefix" => {
        :input => {
          "@subject" => "http://example.com/a",
          "http://example.com/b" => {"@iri" => "http://example.com/c"}
        },
        :context => {"ex" => "http://example.com/"},
        :output => {
          "@context" => {"ex" => "http://example.com/"},
          "@subject" => "ex:a",
          "ex:b" => {"@iri" => "ex:c"}
        }
      },
      "term" => {
        :input => {
          "@subject" => "http://example.com/a",
          "http://example.com/c" => {"@iri" => "http://example.com/c"}
        },
        :context => {"b" => "http://example.com/b"},
        :output => {
          "@context" => {"b" => "http://example.com/b"},
          "@subject" => "http://example.com/a",
          "b" => {"@iri" => "http://example.com/c"}
        }
      },
      "@iri coercion" => {
        :input => {
          "@subject" => "http://example.com/a",
          "http://example.com/b" => "http://example.com/c"
        },
        :context => {"b" => {"@iri" => "http://example.com/b", "@datatype" => "@iri"}},
        :output => {
          "@context" => {"b" => {"@iri" => "http://example.com/b", "@datatype" => "@iri"}},
          "@subject" => "http://example.com/a",
          "b" => "http://example.com/c"
        }
      },
    }.each_pair do |title, params|
      it "processes #{title} with embedded @context" do
        JSON::LD::API.compact(
          params[:context].merge(params[:input]), nil, :debug => @debug
        ).should produce(params[:output], @debug)
      end

      it "processes #{title} with external @context" do
        JSON::LD::API.compact(
          params[:input], params[:context], :debug => @debug
        ).should produce(params[:output], @debug)
      end
    end

    it "uses an @iri coercion"
    it "uses a datatype coercion"
    it "uses a @list coercion"
    it "uses referenced context"
  end
  
  describe ".frame" do
  end
  
  describe ".normalize" do
  end
  
  describe ".triples" do
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
          jld = JSON::LD::API.expand(File.open(filename), (context ? File.open(context) : {}), :debug => @debug)
          jld.should produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(expanded)
        
        it "frame" do
          jld = JSON::LD::API.frame(File.open(filename), File.open(frame), :debug => @debug)
          jld.should produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(framed) && File.exist?(frame)

        it "Turtle" do
          RDF::Graph.load(filename).should be_equivalent_graph(RDF::Graph.load(ttl))
        end if File.exist?(ttl)
      end
    end
  end
end
