# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/reader'

describe JSON::LD::EvaluationContext do
  before(:each) {
    @debug = []
    @ctx_json = %q({
      "@context": {
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
        "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
      }
    })
  }
  subject { JSON::LD::EvaluationContext.new(:debug => @debug, :validate => true)}

  describe "#parse" do
    context "remote" do
      before(:each) do
        @ctx = StringIO.new(@ctx_json)
        def @ctx.content_type; "application/ld+json"; end
      end

      it "retrieves and parses a remote context document" do
        subject.stub(:open).with("http://example.com/context").and_yield(@ctx)
        ec = subject.parse("http://example.com/context")
        ec.provided_context.should produce("http://example.com/context", @debug)
      end

      it "fails given a missing remote @context" do
        subject.stub(:open).with("http://example.com/context").and_raise(IOError)
        lambda {subject.parse("http://example.com/context")}.should raise_error(JSON::LD::InvalidContext, /Failed to parse remote context/)
      end

      it "creates mappings" do
        subject.stub(:open).with("http://example.com/context").and_yield(@ctx)
        ec = subject.parse("http://example.com/context")
        ec.mappings.should produce({
          "name"     => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar"   => "http://xmlns.com/foaf/0.1/avatar"
        }, @debug)
      end
    end

    context "EvaluationContext" do
      it "uses a duplicate of that provided" do
        ec = subject.parse(StringIO.new(@ctx_json))
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

      it "associates list coercion with predicate IRI" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@container" => "@list"}
        }).containers.should produce({
          "http://example.com/" => '@list'
        }, @debug)
      end

      it "associates @id coercion with predicate IRI" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => "@id"}
        }).coercions.should produce({
          "http://example.com/" => "@id"
        }, @debug)
      end

      it "associates datatype coercion with predicate IRI" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => RDF::XSD.string.to_s}
        }).coercions.should produce({
          "http://example.com/" => RDF::XSD.string.to_s
        }, @debug)
      end

      it "expands chains of term definition/use with string values" do
        subject.parse({
          "foo" => "bar",
          "bar" => "baz",
          "baz" => "http://example.com/"
        }).mappings.should produce({
          "foo" => "http://example.com/",
          "bar" => "http://example.com/",
          "baz" => "http://example.com/"
        }, @debug)
      end

      context "with null" do
        it "removes @language if set to null" do
          subject.parse([
            {
              "@language" => "en"
            },
            {
              "@language" => nil
            }
          ]).language.should produce(nil, @debug)
        end

        it "loads initial context" do
          init_ec = JSON::LD::EvaluationContext.new
          nil_ec = subject.parse(nil)
          nil_ec.language.should == init_ec.language
          nil_ec.mappings.should == init_ec.mappings
          nil_ec.coercions.should == init_ec.coercions
          nil_ec.containers.should == init_ec.containers
        end
        
        it "removes a term definition" do
          subject.parse({"name" => nil}).mapping("name").should be_nil
        end
      end

      context "keyword aliases" do
        it "uri for @id as term definition key" do
          subject.parse({
            "uri" => "@id", "foo" => {"uri" => "bar"}
          }).mappings.should produce({
            "uri" => "@id",
            "foo" => "bar"
          }, @debug)
        end

        it 'uri for @id as term definition value' do
          subject.parse({
            "uri" => "@id", "foo" => {"@id" => "bar", "@type" => "uri"}
          }).coercions.should produce({
            "bar" => "@id"
          }, @debug)
        end

        it 'list for @list' do
          subject.parse({
            "container" => "@container", "foo" => {"@id" => "bar", "container" => '@list'}
          }).containers.should produce({
            "bar" => '@list'
          }, @debug)
        end

        it "@iri for @id as term definition key" do
          subject.parse({
            "@iri" => "@id", "foo" => {"@iri" => "bar"}
          }).mappings.should produce({
            "@iri" => "@id",
            "foo" => "bar"
          }, @debug)
        end

        it "@subject for @id as term definition key" do
          subject.parse({
            "@subject" => "@id", "foo" => {"@subject" => "bar"}
          }).mappings.should produce({
            "@subject" => "@id",
            "foo" => "bar"
          }, @debug)
        end

        it 'type for @type' do
          subject.parse({
            "type" => "@type", "foo" => {"@id" => "bar", "type" => "@id"}
          }).coercions.should produce({
            "bar" => "@id"
          }, @debug)
        end
      end
    end

    describe "Syntax Errors" do
      {
        "malformed JSON" => StringIO.new(%q({"@context": {"foo" "http://malformed/"})),
        "no @id, @type, or @list" => {"foo" => {}},
        "value as array" => {"foo" => []},
        "@id as object" => {"foo" => {"@id" => {}}},
        "@id as array" => {"foo" => {"@id" => []}},
        "@type as object" => {"foo" => {"@type" => {}}},
        "@type as array" => {"foo" => {"@type" => []}},
        "@type as @list" => {"foo" => {"@type" => "@list"}},
        "@list as object" => {"foo" => {"@list" => {}}},
        "@list as array" => {"foo" => {"@list" => []}},
        "@list as string" => {"foo" => {"@list" => "true"}},
        "invalid term" => {"_:foo" => {"@id" => "http://example.com/"}},
      }.each do |title, context|
        it title do
          #subject.parse(context)
          lambda {
            ec = subject.parse(context)
            ec.serialize.should produce({}, @debug)
          }.should raise_error(JSON::LD::InvalidContext::Syntax)
        end
      end
    end

    describe "Load Errors" do
      {
        "fixme" => "FIXME",
      }.each do |title, context|
        it title do
          lambda { subject.parse(context) }.should raise_error(JSON::LD::InvalidContext::LoadError)
        end
      end
    end
  end

  describe "#serialize" do
    it "uses provided context document" do
      ctx = StringIO.new(@ctx_json)
      def ctx.content_type; "application/ld+json"; end

      subject.stub(:open).with("http://example.com/context").and_yield(ctx)
      ec = subject.parse("http://example.com/context")
      ec.serialize.should produce({
        "@context" => "http://example.com/context"
      }, @debug)
    end

    it "uses provided context array" do
      ctx = [
        {"foo" => "bar"},
        {"baz" => "bob"}
      ]

      ec = subject.parse(ctx)
      ec.serialize.should produce({
        "@context" => ctx
      }, @debug)
    end

    it "uses provided context hash" do
      ctx = {"foo" => "bar"}

      ec = subject.parse(ctx)
      ec.serialize.should produce({
        "@context" => ctx
      }, @debug)
    end

    it "@language" do
      subject.language = "en"
      subject.serialize.should produce({
        "@context" => {
          "@language" => "en"
        }
      }, @debug)
    end

    it "term mappings" do
      subject.set_mapping("foo", "bar")
      subject.serialize.should produce({
        "@context" => {
          "foo" => "bar"
        }
      }, @debug)
    end

    it "@type with dependent prefixes in a single context" do
      subject.set_mapping("xsd", RDF::XSD.to_uri)
      subject.set_mapping("homepage", RDF::FOAF.homepage)
      subject.coerce(RDF::FOAF.homepage, "@id")
      subject.serialize.should produce({
        "@context" => {
          "xsd" => RDF::XSD.to_uri,
          "homepage" => {"@id" => RDF::FOAF.homepage.to_s, "@type" => "@id"}
        }
      }, @debug)
    end

    it "@list with @id definition in a single context" do
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_container(RDF::FOAF.knows, '@list')
      subject.serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "prefix with @type and @list" do
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.coerce(RDF::FOAF.knows, "@id")
      subject.set_container(RDF::FOAF.knows, '@list')
      subject.serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@type" => "@id", "@container" => "@list"}
        }
      }, @debug)
    end

    it "CURIE with @type" do
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_container(RDF::FOAF.knows, '@list')
      subject.serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri,
          "foaf:knows" => {"@container" => "@list"}
        }
      }, @debug)
    end

    it "uses aliased @id in key position" do
      subject.set_mapping("id", '@id')
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_container(RDF::FOAF.knows, '@list')
      subject.serialize.should produce({
        "@context" => {
          "id" => "@id",
          "knows" => {"id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "uses aliased @id in value position" do
      subject.set_mapping("id", "@id")
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.coerce(RDF::FOAF.homepage, "@id")
      subject.serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri.to_s,
          "id" => "@id",
          "foaf:homepage" => {"@type" => "id"}
        }
      }, @debug)
    end

    it "uses aliased @type" do
      subject.set_mapping("type", "@type")
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.coerce(RDF::FOAF.homepage, "@id")
      subject.serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri.to_s,
          "type" => "@type",
          "foaf:homepage" => {"type" => "@id"}
        }
      }, @debug)
    end

    it "uses aliased @container" do
      subject.set_mapping("container", '@container')
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_container(RDF::FOAF.knows, '@list')
      subject.serialize.should produce({
        "@context" => {
          "container" => "@container",
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "container" => "@list"}
        }
      }, @debug)
    end

      
    context "extra keys or values" do
      {
        "extra key" => {
          :input => {"foo" => {"@id" => "http://example.com/foo", "@baz" => "foobar"}},
          :result => {"@context" => {"foo" => "http://example.com/foo"}}
        }
      }.each do |title, params|
        it title do
          ec = subject.parse(params[:input])
          ec.serialize.should produce(params[:result], @debug)
        end
      end
    end

  end

  describe "#expand_iri" do
    before(:each) do
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("", RDF::URI("http://empty/"))
    end

    {
      "absolute IRI" =>  ["http://example.org/", RDF::URI("http://example.org/")],
      "term" =>          ["ex",                  RDF::URI("http://example.org/")],
      "prefix:suffix" => ["ex:suffix",           RDF::URI("http://example.org/suffix")],
      "keyword" =>       ["@type",               "@type"],
      "empty" =>         [":suffix",             RDF::URI("http://empty/suffix")],
      "unmapped" =>      ["foo",                 RDF::URI("foo")],
      "empty term" =>    ["",                    RDF::URI("http://empty/")],
      "another abs IRI"=>["ex://foo",            RDF::URI("ex://foo")],
    }.each do |title, (input,result)|
      it title do
        subject.expand_iri(input).should produce(result, @debug)
      end
    end

    it "bnode" do
      subject.expand_iri("_:a").should be_a(RDF::Node)
    end

    context "with base IRI" do
      before(:each) do
        subject.instance_variable_set(:@base, RDF::URI("http://example.org/"))
        subject.mappings.delete("")
      end

      {
        "base" =>     ["",            RDF::URI("http://example.org/")],
        "relative" => ["a/b",         RDF::URI("http://example.org/a/b")],
        "hash" =>     ["#a",          RDF::URI("http://example.org/#a")],
        "absolute" => ["http://foo/", RDF::URI("http://foo/")]
      }.each do |title, (input,result)|
        it title do
          subject.expand_iri(input).should produce(result, @debug)
        end
      end
    end
  end

  describe "#compact_iri" do
    before(:each) do
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("", RDF::URI("http://empty/"))
    end

    {
      "absolute IRI" =>  ["http://example.com/", RDF::URI("http://example.com/")],
      "term" =>          ["ex",                  RDF::URI("http://example.org/")],
      "prefix:suffix" => ["ex:suffix",           RDF::URI("http://example.org/suffix")],
      "keyword" =>       ["@type",               "@type"],
      "empty" =>         [":suffix",             RDF::URI("http://empty/suffix")],
      "unmapped" =>      ["foo",                 RDF::URI("foo")],
      "bnode" =>         ["_:a",                 RDF::Node("a")],
    }.each do |title, (result, input)|
      it title do
        subject.compact_iri(input).should produce(result, @debug)
      end
    end
  end

  describe "#expand_value" do
    before(:each) do
      subject.set_mapping("dc", RDF::DC.to_uri)
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_mapping("xsd", RDF::XSD.to_uri)
      subject.coerce(RDF::FOAF.age, RDF::XSD.integer)
      subject.coerce(RDF::FOAF.knows, "@id")
      subject.coerce(RDF::DC.created, RDF::XSD.date)
    end

    {
      "absolute IRI" =>   ["foaf:knows",  "http://example.com/",  {"@id" => "http://example.com/"}],
      "term" =>           ["foaf:knows",  "ex",                   {"@id" => "http://example.org/"}],
      "prefix:suffix" =>  ["foaf:knows",  "ex:suffix",            {"@id" => "http://example.org/suffix"}],
      "no IRI" =>         ["foo",         "http://example.com/",  "http://example.com/"],
      "no term" =>        ["foo",         "ex",                   "ex"],
      "no prefix" =>      ["foo",         "ex:suffix",            "ex:suffix"],
      "integer" =>        ["foaf:age",    "54",                   {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "date " =>          ["dc:created",  "2011-12-27Z",          {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "native boolean" => ["foo", true,                           true],
      "native integer" => ["foo", 1,                              {"@value" => "1", "@type" => RDF::XSD.integer.to_s}],
      "native double" =>  ["foo", 1.1,                            {"@value" => "1.1000000000000001E0", "@type" => RDF::XSD.double.to_s}],
      "native date" =>    ["foo", Date.parse("2011-12-27Z"),      {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "native time" =>    ["foo", Time.parse("10:11:12Z"),        {"@value" => "10:11:12Z", "@type" => RDF::XSD.time.to_s}],
      "native dateTime" =>["foo", DateTime.parse("2011-12-27T10:11:12Z"), {"@value" => "2011-12-27T10:11:12Z", "@type" => RDF::XSD.dateTime.to_s}],
      "rdf boolean" =>    ["foo", RDF::Literal(true),             true],
      "rdf integer" =>    ["foo", RDF::Literal(1),                {"@value" => "1", "@type" => RDF::XSD.integer.to_s}],
      "rdf decimal" =>    ["foo", RDF::Literal::Decimal.new(1.1), {"@value" => "1.1", "@type" => RDF::XSD.decimal.to_s}],
      "rdf double" =>     ["foo", RDF::Literal::Double.new(1.1),  {"@value" => "1.1000000000000001E0", "@type" => RDF::XSD.double.to_s}],
      "rdf URI" =>        ["foo", RDF::URI("foo"),                {"@id" => "foo"}],
      "rdf date " =>      ["foo", RDF::Literal(Date.parse("2011-12-27Z")), {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
    }.each do |title, (key, compacted, expanded)|
      it title do
        predicate = subject.expand_iri(key)
        subject.expand_value(predicate, compacted).should produce(expanded, @debug)
      end
    end

    context "@language" do
      {
        "no IRI" =>         ["foo",         "http://example.com/",  {"@value" => "http://example.com/", "@language" => "en"}],
        "no term" =>        ["foo",         "ex",                   {"@value" => "ex", "@language" => "en"}],
        "no prefix" =>      ["foo",         "ex:suffix",            {"@value" => "ex:suffix", "@language" => "en"}],
        "native boolean" => ["foo",         true,                   true],
        "native integer" => ["foo",         1,                      {"@value" => "1", "@type" => RDF::XSD.integer.to_s}],
        "native double" =>  ["foo",         1.1,                    {"@value" => "1.1000000000000001E0", "@type" => RDF::XSD.double.to_s}],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.language = "en"
          predicate = subject.expand_iri(key)
          subject.expand_value(predicate, compacted).should produce(expanded, @debug)
        end
      end
    end
  end

  describe "compact_value" do
    before(:each) do
      subject.set_mapping("dc", RDF::DC.to_uri)
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_mapping("xsd", RDF::XSD.to_uri)
      subject.coerce(RDF::FOAF.age, RDF::XSD.integer)
      subject.coerce(RDF::FOAF.knows, "@id")
      subject.coerce(RDF::DC.created, RDF::XSD.date)
    end

    {
      "absolute IRI" =>   ["foaf:knows",  "http://example.com/",  {"@id" => "http://example.com/"}],
      "term" =>           ["foaf:knows",  "ex",                   {"@id" => "http://example.org/"}],
      "prefix:suffix" =>  ["foaf:knows",  "ex:suffix",            {"@id" => "http://example.org/suffix"}],
      "integer" =>        ["foaf:age",    54,                     {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "date " =>          ["dc:created",  "2011-12-27Z",          {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "no IRI" =>         ["foo", {"@id" => "http://example.com/"},  {"@id" => "http://example.com/"}],
      "no IRI (term)" =>  ["foo", {"@id" => "ex"},                {"@id" => "http://example.org/"}],
      "no IRI (CURIE)" => ["foo", {"@id" => "foaf:Person"},       {"@id" => RDF::FOAF.Person.to_s}],
      "no boolean" =>     ["foo", true,                           {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}],
      "no integer" =>     ["foo", 54,                             {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "no date " =>       ["foo", {"@value" => "2011-12-27Z", "@type" => "xsd:date"}, {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "no string " =>     ["foo", "string",                       {"@value" => "string"}],
    }.each do |title, (key, compacted, expanded)|
      it title do
        predicate = subject.expand_iri(key)
        subject.compact_value(predicate, expanded).should produce(compacted, @debug)
      end
    end

    context "@language" do
      {
        "@id"                            => ["foo", {"@id" => "foo"},                                   {"@id" => "foo"}],
        "integer"                        => ["foo", 54,                                                 {"@value" => "54", "@type" => "xsd:integer"}],
        "date"                           => ["foo", {"@value" => "2011-12-27Z","@type" => "xsd:date"},{"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
        "no lang"                        => ["foo", {"@value" => "foo"  },                            {"@value" => "foo"}],
        "same lang"                      => ["foo", "foo",                                              {"@value" => "foo", "@language" => "en"}],
        "other lang"                     => ["foo",  {"@value" => "foo", "@language" => "bar"},       {"@value" => "foo", "@language" => "bar"}],
        "no lang with @type coercion"    => ["dc:created", {"@value" => "foo"},                       {"@value" => "foo"}],
        "no lang with @id coercion"      => ["foaf:knows", {"@value" => "foo"},                       {"@value" => "foo"}],
        "same lang with @type coercion"  => ["dc:created", {"@value" => "foo"},                       {"@value" => "foo"}],
        "same lang with @id coercion"    => ["foaf:knows", {"@value" => "foo"},                       {"@value" => "foo"}],
        "other lang with @type coercion" => ["dc:created", {"@value" => "foo", "@language" => "bar"}, {"@value" => "foo", "@language" => "bar"}],
        "other lang with @id coercion"   => ["foaf:knows", {"@value" => "foo", "@language" => "bar"}, {"@value" => "foo", "@language" => "bar"}],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.language = "en"
          predicate = subject.expand_iri(key)
          subject.compact_value(predicate, expanded).should produce(compacted, @debug)
        end
      end
    end

    [[], true, false, 1, 1.1, "string"].each do |v|
      it "raises error given #{v.class}" do
        lambda {subject.compact_value("foo", v)}.should raise_error(JSON::LD::ProcessingError::Lossy)
      end
    end

    context "keywords" do
      before(:each) do
        subject.set_mapping("id", "@id")
        subject.set_mapping("type", "@type")
        subject.set_mapping("list", "@list")
        subject.set_mapping("language", "@language")
        subject.set_mapping("literal", "@value")
      end

      {
        "@id" =>      [{"id" => "http://example.com/"},             {"@id" => "http://example.com/"}],
        "@type" =>    [{"literal" => "foo", "type" => "bar"},       {"@value" => "foo", "@type" => "bar"}],
        "@value" =>   [{"literal" => "foo", "language" => "bar"},   {"@value" => "foo", "@language" => "bar"}],
        "@list" =>    [{"list" => ["foo"]},                         {"@list" => ["foo"]  }],
      }.each do |title, (compacted, expanded)|
        it title do
          subject.compact_value("foo", expanded).should produce(compacted, @debug)
        end
      end
    end
  end
end
