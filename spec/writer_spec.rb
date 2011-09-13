# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/writer'

describe JSON::LD::Writer do
  before :each do
    @writer = JSON::LD::Writer.new(StringIO.new(""))
  end

  it_should_behave_like RDF_Writer

  describe ".for" do
    formats = [
      :json, :ld, :jsonld,
      'etc/doap.json', "etc/doap.jsonld",
      {:file_name      => 'etc/doap.json'},
      {:file_name      => 'etc/doap.jsonld'},
      {:file_extension => 'json'},
      {:file_extension => 'jsonld'},
      {:content_type   => 'application/ld+json'},
      {:content_type   => 'application/x-ld+json'},
    ].each do |arg|
      it "discovers with #{arg.inspect}" do
        RDF::Writer.for(arg).should == JSON::LD::Writer
      end
    end
  end

  describe ".for" do
    formats = [
      :json, :ld, :jsonld,
      'etc/doap.json', "etc/doap.jsonld",
      {:file_name      => 'etc/doap.json'},
      {:file_name      => 'etc/doap.jsonld'},
      {:file_extension => 'json'},
      {:file_extension => 'jsonld'},
      {:content_type   => 'application/ld+json'},
      {:content_type   => 'application/x-ld+json'},
    ].each do |arg|
      it "discovers with #{arg.inspect}" do
        RDF::Reader.for(arg).should == JSON::LD::Reader
      end
    end
  end

  context "simple tests" do
    it "should use full URIs without base" do
      input = %(<http://a/b> <http://a/c> <http://a/d> .)
      serialize(input).should produce({
        '@context'       => {'@coerce' => {'@iri' => "http://a/c"}},
        '@subject'       => "http://a/b",
        "http://a/c"  => "http://a/d"
      }, @debug)
    end

    it "should use qname URIs with prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      serialize(input, :standard_prefixes => true).
      should produce({
        '@context' => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          '@coerce'  => {'@iri' => "foaf:c"}},
        '@subject'   => "foaf:b",
        "foaf:c"  => "foaf:d"
      }, @debug)
    end

    it "should use CURIEs with empty prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      serialize(input, :prefixes => { "" => RDF::FOAF}).
      should produce({
        '@context' => {""=>"http://xmlns.com/foaf/0.1/", '@coerce'=>{'@iri'=>":c"}},
        '@subject' => ":b",
        ":c"    => ":d"
      }, @debug)
    end
    
    it "should use CURIEs with empty suffix" do
      input = %(<http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> .)
      serialize(input, :standard_prefixes => true).
      should produce({
        '@context'=>{
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          '@coerce'  => {'@iri'=>"foaf:"}},
        '@subject'   => "foaf:",
        "foaf:"   => "foaf:"
      }, @debug)
    end
    
    it "should not use CURIE with illegal local part" do
      input = %(
        @prefix db: <http://dbpedia.org/resource/> .
        @prefix dbo: <http://dbpedia.org/ontology/> .
        db:Michael_Jackson dbo:artistOf <http://dbpedia.org/resource/%28I_Can%27t_Make_It%29_Another_Day> .
      )

      serialize(input, :prefixes => {
          "db" => RDF::URI("http://dbpedia.org/resource/"),
          "dbo" => RDF::URI("http://dbpedia.org/ontology/")}).
      should produce({
        '@context'   => {
          "db"    => "http://dbpedia.org/resource/",
          "dbo"   => "http://dbpedia.org/ontology/",
          '@coerce'  => {'@iri'=>"dbo:artistOf"}
        },
        '@subject'   => "db:Michael_Jackson",
        "dbo:artistOf" => "db:%28I_Can%27t_Make_It%29_Another_Day"
      }, @debug)
    end

    it "should order literal values" do
      input = %(@base <http://a/> . <b> <c> "e", "d" .)
      serialize(input).
      should produce({
        '@subject'       => "http://a/b",
        "http://a/c"  => ["d", "e"]
      }, @debug)
    end

    it "should order URI values" do
      input = %(@base <http://a/> . <b> <c> <e>, <d> .)
      serialize(input).
      should produce({
        '@context'       => {'@coerce' => {'@iri' => "http://a/c"}},
        '@subject'       => "http://a/b",
        "http://a/c"  => ["http://a/d", "http://a/e"]
      }, @debug)
    end

    it "should order properties" do
      input = %(
        @prefix : <http://xmlns.com/foaf/0.1/> .
        @prefix dc: <http://purl.org/dc/elements/1.1/> .
        @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
        :b :c :d .
        :b dc:title "title" .
        :b a :class .
        :b rdfs:label "label" .
      )
      serialize(input, :prefixes => {"" => RDF::FOAF, "dc" => RDF::DC11}).
      should produce({
        '@context'   => {
          ""      => "http://xmlns.com/foaf/0.1/",
          "dc"    => "http://purl.org/dc/elements/1.1/",
          "rdfs"  => "http://www.w3.org/2000/01/rdf-schema#",
          '@coerce'  => {'@iri' => ":c"}
        },
        '@subject'       => ":b",
        '@type'          => ":class",
        "dc:title"    => "title",
        "rdfs:label"  => "label",
        ":c"          => ":d"
      }, @debug)
    end
    
    it "should generate object list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :b :c :d, :e .)
      serialize(input, :prefixes => {"" => RDF::FOAF}).
      should produce({
        '@context' => {
          ""=>"http://xmlns.com/foaf/0.1/",
          '@coerce' => {'@iri'=>":c"}},
        '@subject'        => ":b",
        ":c"       => [":d", ":e"]
      }, @debug)
    end
    
    it "should generate property list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :b :c :d; :e :f .)
      serialize(input, :prefixes => {"" => RDF::FOAF}).
      should produce({
        '@context' => {
          ""      => "http://xmlns.com/foaf/0.1/",
          '@coerce'  => {'@iri'=>[":c", ":e"]}},
        '@subject'   => ":b",
        ":c"      => ":d",
        ":e"      => ":f"
      }, @debug)
    end
    
    it "serializes multiple subjects" do
      input = %q(
        @prefix : <http://www.w3.org/2006/03/test-description#> .
        @prefix dc: <http://purl.org/dc/elements/1.1/> .
        <test-cases/0001> a :TestCase .
        <test-cases/0002> a :TestCase .
      )
      serialize(input, :prefixes => {"" => "http://www.w3.org/2006/03/test-description#"}).
      should produce({
        '@context'     => {""=>"http://www.w3.org/2006/03/test-description#"},
        '@subject'     => [
          {'@subject'  => "test-cases/0001", '@type' => ":TestCase"},
          {'@subject'  => "test-cases/0002", '@type' => ":TestCase"}
        ]
      }, @debug)
    end
  end
  
  context "literals" do
    it "coerces typed literal" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"^^ex:d .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        '@context'   => {
          "ex"    => "http://example.com/",
          '@coerce'  => {"ex:d" => "ex:b"}},
        '@subject'   => "ex:a",
        "ex:b"    => "foo"
      }, @debug)
    end

    it "coerces integer" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1 .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        '@context'   => {
          "ex"    => "http://example.com/"},
        '@subject'   => "ex:a",
        "ex:b"    => 1
      }, @debug)
    end

    it "coerces boolean" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b true .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        '@context'   => {
          "ex"    => "http://example.com/"},
        '@subject'   => "ex:a",
        "ex:b"    => true
      }, @debug)
    end

    it "coerces decmal" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0 .)
      serialize(input, :prefixes => {:ex => "http://example.com/", :xsd => RDF::XSD}).should produce({
        '@context'   => {
          "ex"    => "http://example.com/",
          '@coerce'  => {"xsd:decimal" => "ex:b"}},
        '@subject'   => "ex:a",
        "ex:b"    => "1.0"
      }, @debug)
    end

    it "coerces double" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0e0 .)
      serialize(input, :prefixes => {:ex => "http://example.com/", :xsd => RDF::XSD}).should produce({
        '@context'   => {
          "ex"    => "http://example.com/",
          '@coerce'  => {"xsd:double" => "ex:b"}},
        '@subject'   => "ex:a",
        "ex:b"    => "1.0e0"
      }, @debug)
    end
    
    it "encodes language literal" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"@en-us .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        '@context'   => {
          "ex"    => "http://example.com/"},
        '@subject'   => "ex:a",
        "ex:b"    => {'@literal' => "foo", '@language' => "en-us"}
      }, @debug)
    end
  end

  context "anons" do
    it "should generate bare anon" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . [:a :b] .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          '@coerce'  => {'@iri'=>"foaf:a"}
        },
        "foaf:a"  => "foaf:b"
      }, @debug)
    end
    
    it "should generate anon as subject" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . [:a :b] :c :d .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          '@coerce'  => {'@iri'=>["foaf:a","foaf:c"]}
        },
        "foaf:a"  => "foaf:b",
        "foaf:c"  => "foaf:d"
      }, @debug)
    end
    
    it "should generate anon as object" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b [:c :d] .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          '@coerce'  => {'@iri'=>["foaf:b","foaf:c"]}
        },
        '@subject'     => "foaf:a",
        "foaf:b"    => {
          "foaf:c"  => "foaf:d"
        }
      }, @debug)
    end
  end
  
  context "lists" do
    it "should generate bare list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . (:a :b) .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        },
        '@subject' => {'@list' => [{'@subject' => "foaf:a"}, {'@subject' => "foaf:b"}]}
      }, @debug)
    end

    it "should generate literal list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b ( "apple" "banana" ) .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          '@coerce'  => {'@iri'=>"foaf:b"}
        },
        '@subject'   => "foaf:a",
        "foaf:b"  => {'@list' => ["apple", "banana"]}
      }, @debug)
    end
    
    it "should generate empty list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b () .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          '@coerce'  => {'@iri'=>"foaf:b"}
        },
        '@subject'   => "foaf:a",
        "foaf:b"  => {'@list' => []}
      }, @debug)
    end
    
    it "should generate single element list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b ( "apple" ) .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          '@coerce'  => {'@iri'=>"foaf:b"}
        },
        '@subject'   => "foaf:a",
        "foaf:b"  => {'@list' => ["apple"]}
      }, @debug)
    end
    
    it "should generate single element list without @coerce" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b ( [ :b "foo" ] ) .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        },
        '@subject'   => "foaf:a",
        "foaf:b"  => {"@list" => [{"foaf:b" => "foo"}]}
      }, @debug)
    end

    it "should generate empty list as subject" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . () :a :b .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          '@coerce'  => {'@iri'=>"foaf:a"}
        },
        '@subject'   => {'@list' => []},
        "foaf:a"  => "foaf:b"
      }, @debug)
    end
    
    it "should generate list as subject" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . (:a) :b :c .)
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          '@coerce'  => {'@iri'=>"foaf:b"}
        },
        '@subject'   => {'@list' => [{'@subject' => "foaf:a"}]},
        "foaf:b"  => "foaf:c"
      }, @debug)
    end

    it "should generate list of lists" do
      input = %(
        @prefix : <http://xmlns.com/foaf/0.1/> .
        @prefix owl: <http://www.w3.org/2002/07/owl#> .
        :listOf2Lists owl:sameAs (() (1)) .
      )
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "owl"   => "http://www.w3.org/2002/07/owl#",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          '@coerce'  => {'@iri'=>"owl:sameAs"}
        },
        '@subject'       => "foaf:listOf2Lists",
        "owl:sameAs"  => {'@list' => [
          {'@list' => []},
          {'@list' => [1]}
        ]}
      }, @debug)
    end
    
    it "should generate list anon" do
      input = %(
        @prefix : <http://xmlns.com/foaf/0.1/> .
        @prefix owl: <http://www.w3.org/2002/07/owl#> .
        :twoAnons owl:sameAs ([a :mother] [a :father]) .
      )
      serialize(input, :standard_prefixes => true).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "owl"   => "http://www.w3.org/2002/07/owl#",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          '@coerce'  => {'@iri'=>"owl:sameAs"}
        },
        '@subject'       => "foaf:twoAnons",
        "owl:sameAs"  => {'@list' => [
          {'@type' => "foaf:mother"},
          {'@type' => "foaf:father"}
        ]}
      }, @debug)
    end
    
    it "should generate owl:unionOf list" do
      input = %(
        @prefix : <http://xmlns.com/foaf/0.1/> .
        @prefix owl: <http://www.w3.org/2002/07/owl#> .
        @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
        @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
        :a rdfs:domain [
          a owl:Class;
          owl:unionOf [
            a owl:Class;
            rdf:first :b;
            rdf:rest [
              a owl:Class;
              rdf:first :c;
              rdf:rest rdf:nil
            ]
          ]
        ] .
      )
      serialize(input, :coerce => {RDF::OWL.unionOf.to_s => '@iri'}, :standard_prefixes => true ).should produce({
        '@context'   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "owl"   => "http://www.w3.org/2002/07/owl#",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          "rdfs"  => "http://www.w3.org/2000/01/rdf-schema#",
          '@coerce'  => {'@iri'=>["rdfs:domain", "owl:unionOf"]}
        },
        '@subject'         => "foaf:a",
        "rdfs:domain"   => {
          '@type'          => "owl:Class",
          "owl:unionOf" => {'@list' => ["foaf:b", "foaf:c"]}
        }
      }, @debug)
    end
  end

  context "context" do
    context "base" do
      it "shortens URIs" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        serialize(input, :base_uri => "http://a/").should produce({
          '@context'       => {
            '@base'        => "http://a/",
            '@coerce'      => {'@iri' => "http://a/c"}},
          '@subject'       => "b",
          "http://a/c"  => "d"
        }, @debug)
      end
    end
    
    context "vocab" do
      it "shortens URIs" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        serialize(input, :vocab => "http://a/").should produce({
          '@context'   => {
            '@vocab'   => "http://a/",
            '@coerce'  => {'@iri' => "c"}},
          '@subject'   => "http://a/b",
          "c"       => "http://a/d"
        }, @debug)
      end
    end
    
    context "coerce" do
      it "does not coerce properties with hetrogeneous types" do
        input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b :c, "d" .)
        serialize(input, :standard_prefixes => true).should produce({
          '@context'   => {"foaf"  => "http://xmlns.com/foaf/0.1/"},
          '@subject'   => "foaf:a",
          "foaf:b"  => ["d", {'@iri'=>"foaf:c"}]
        }, @debug)
      end
      
      it "does not coerce properties with hetgogeneous literal datatype" do
        input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b "c", "d"@en, "f"^^:g .)
        serialize(input, :standard_prefixes => true).should produce({
          '@context'   => {"foaf"  => "http://xmlns.com/foaf/0.1/"},
          '@subject'   => "foaf:a",
          "foaf:b"  => ["c", {'@literal' => "d", '@language' => "en"}, {'@literal' => "f", '@datatype' => "foaf:g"}]
        }, @debug)
      end
    end
  end
  
  context "normalization" do
    [
      [
        %q(<http://a/b> <http://a/c> <http://a/d> .),
        %q({"@subject":"http://a/b","http://a/c":{"@iri":"http://a/d"}})
      ],
      [
        %q(<http://a/b> <http://a/c> "d" .),
        %q({"@subject":"http://a/b","http://a/c":{"@literal":"d"}})
      ],
      [
        %q(<http://a/b> <http://a/c> "e", "d" .),
        %q({"@subject":"http://a/b","http://a/c":[{"@literal":"d"},{"@literal":"e"}]})
      ],
    ].each do |(input,output)|
      it "serializes #{input.inspect} to #{output.inspect}" do
        g = parse(input)
        result = JSON::LD::Writer.buffer(:normalize => true) {|writer| writer << g}
        result.should == output
      end
    end
  end
  
  def parse(input, options = {})
    RDF::Graph.new << RDF::Turtle::Reader.new(input, options)
  end

  # Serialize ntstr to a string and compare against regexps
  def serialize(ntstr, options = {})
    g = parse(ntstr, options)
    @debug = [] << g.dump(:ttl)
    result = JSON::LD::Writer.hash(options.merge(:debug => @debug)) do |writer|
      writer << g
    end
    if $verbose
      #puts hash.to_json
    end
    
    result
  end
end
