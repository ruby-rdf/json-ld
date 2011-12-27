# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/reader'

describe JSON::LD::EvaluationContext do
  before :each do
    @context = JSON::LD::EvaluationContext.new()
  end

  describe "#parse" do
    before(:each) { @debug = [] }
    subject { JSON::LD::EvaluationContext.new(:debug => @debug, :validate => true)}

    context "remote" do
      before(:each) do
        @ctx = StringIO.new(%q({
          "@context": {
            "name": "http://xmlns.com/foaf/0.1/name",
            "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
            "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
          }
        }))
        def @ctx.content_type; "application/ld+json"; end
        def @ctx.base_uri; "http://example.com/context"; end
      end

      it "retrieves and parses a remote context document" do
        subject.stub(:open).with(@ctx.base_uri).and_yield(@ctx)
        ec = subject.parse(@ctx.base_uri)
        ec.provided_context.should produce(@ctx.base_uri, @debug)
      end

      it "fails given a missing remote @context" do
        subject.stub(:open).with(@ctx.base_uri).and_raise(IOError)
        lambda {subject.parse(@ctx.base_uri)}.should raise_error(IOError, /Failed to parse remote context/)
      end
      
      it "creates mappings" do
        subject.stub(:open).with(@ctx.base_uri).and_yield(@ctx)
        ec = subject.parse(@ctx.base_uri)
        ec.mappings.should produce({
          "name"     => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar"   => "http://xmlns.com/foaf/0.1/avatar"
        }, @debug)
      end
    end

    context "EvaluationContext", :pending => true do
      it "uses a duplicate of that provided" do
        ec = subject.parse(subject)
        ec.mappings.should produce({
          "name"     => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar"   => "http://xmlns.com/foaf/0.1/avatar"
        }, @debug)
      end
    end

    context "Array" do
      before(:all) do
        @ctx = [
          {"foo" => "http://example.com/foo"},
          {"bar" => "foo"}
        ]
      end
      
      it "merges definitions from each context" do
        ec = subject.parse(@ctx)
        ec.mappings.should produce({
          "foo" => "http://example.com/foo",
          "bar" => "http://example.com/foo"
        }, @debug)
      end
    end

    context "Hash" do
      it "extracts @base" do
        subject.parse({
          "@base" => "http://example.com/"
        }).base.should produce("http://example.com/", @debug)
      end

      it "extracts @vocab" do
        subject.parse({
          "@vocab" => "http://example.com/"
        }).vocab.should produce("http://example.com/", @debug)
      end

      it "extracts @language" do
        subject.parse({
          "@language" => "en"
        }).language.should produce("en", @debug)
      end

      it "maps term with IRI value" do
        subject.parse({
          "foo" => "http://example.com/"
        }).mappings.should produce({
          "foo" => "http://example.com/"
        }, @debug)
      end

      it "maps term with @id" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/"}
        }).mappings.should produce({
          "foo" => "http://example.com/"
        }, @debug)
      end

      it "Associates list coercion with predicate IRI" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@list" => true}
        }).list.should produce({
          "http://example.com/" => true
        }, @debug)
      end

      it "Associates @id coercion with predicate IRI" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => "@id"}
        }).coerce.should produce({
          "http://example.com/" => "@id"
        }, @debug)
      end

      it "Associates datatype coercion with predicate IRI" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => RDF::XSD.string.to_s}
        }).coerce.should produce({
          "http://example.com/" => RDF::XSD.string.to_s
        }, @debug)
      end
    end
    
    describe "#serialize" do
      it "uses provided context document"
      
      it "uses provided context array"
      
      it "uses provided context hash"
      
      it "serializes @base, @vocab and @language"
      
      it "serializes term mappings"
      
      it "serializes @type with dependent prefixes in two contexts"
      
      it "serializes @type without dependend prefixes in a single context"
      
      it "serializes @list with dependent prefixes in two contexts"
      
      it "serializes @list without dependend prefixes in a single context"
      
      it "serializes prefix with @type and @list"
      
      it "serializes CURIE with @type"
    end
    
    describe "#expand_iri" do
      it "FIXME"
    end
    
    describe "#compact_iri" do
      it "FIXME"
    end
    
    describe "#expand_value" do
      it "FIXME"
    end
    
    describe "compact_value" do
      it "FIXME"
    end
  end
end
