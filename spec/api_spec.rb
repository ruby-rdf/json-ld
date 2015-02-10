# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe "#initialize" do
    context "with string input" do
      let(:context) do
        JSON::LD::API::RemoteDocument.new("http://example.com/context", %q({
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "name": "http://xmlns.com/foaf/0.1/name",
            "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
            "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
          }
        }))
      end
      let(:remote_doc) do
        JSON::LD::API::RemoteDocument.new("http://example.com/foo", %q({
          "@id": "",
          "name": "foo"
        }), "http://example.com/context")
      end

      it "loads document with loader and loads context" do
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/foo", anything).and_return(remote_doc)
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context", anything).and_yield(context)
        JSON::LD::API.new("http://example.com/foo", nil)
      end
    end

    context "with RDF::Util::File::RemoteDoc input" do
      let(:context) do
        JSON::LD::API::RemoteDocument.new("http://example.com/context", %q({
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "name": "http://xmlns.com/foaf/0.1/name",
            "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
            "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
          }
        }))
      end
      let(:remote_doc) do
        RDF::Util::File::RemoteDocument.new(%q({"@id": "", "name": "foo"}),
          headers: {
            content_type: 'application/json',
            link: %(<http://example.com/context>; rel="http://www.w3.org/ns/json-ld#context"; type="application/ld+json")
          }
        )
      end

      it "processes document and retrieves linked context" do
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context", anything).and_yield(context)
        JSON::LD::API.new(remote_doc, nil)
      end
    end
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
        it "expands" do
          options = {debug: @debug}
          options[:expandContext] = File.open(context) if context
          jld = JSON::LD::API.expand(File.open(filename), options)
          expect(jld).to produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(expanded)
        
        it "compacts" do
          jld = JSON::LD::API.compact(File.open(filename), File.open(context), debug: @debug)
          expect(jld).to produce(JSON.load(File.open(compacted)), @debug)
        end if File.exist?(compacted) && File.exist?(context)
        
        it "frame" do
          jld = JSON::LD::API.frame(File.open(filename), File.open(frame), debug: @debug)
          expect(jld).to produce(JSON.load(File.open(framed)), @debug)
        end if File.exist?(framed) && File.exist?(frame)

        it "toRdf" do
          expect(RDF::Repository.load(filename, debug: @debug)).to be_equivalent_graph(RDF::Repository.load(ttl), trace: @debug)
        end if File.exist?(ttl)
      end
    end
  end
end
