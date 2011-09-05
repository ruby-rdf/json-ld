# coding: utf-8
$:.unshift "."
require File.join(File.dirname(__FILE__), 'spec_helper')

describe JSON::LD::Writer do
  context "simple tests" do
    it "should use full URIs without base" do
      input = %(<http://a/b> <http://a/c> <http://a/d> .)
      serialize(input).should produce({
        CONTEXT       => {COERCE => {IRI => "http://a/c"}},
        SUBJECT       => "http://a/b",
        "http://a/c"  => "http://a/d"
      }, @debug)
    end

    it "should use qname URIs with prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      serialize(input, :standard_prefixes => true).
      should produce({
        CONTEXT => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          COERCE  => {IRI => "foaf:c"}},
        SUBJECT   => "foaf:b",
        "foaf:c"  => "foaf:d"
      }, @debug)
    end

    it "should use CURIEs with empty prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      serialize(input, :prefixes => { "" => RDF::FOAF}).
      should produce({
        CONTEXT => {""=>"http://xmlns.com/foaf/0.1/", COERCE=>{IRI=>":c"}},
        SUBJECT => ":b",
        ":c"    => ":d"
      }, @debug)
    end
    
    it "should use CURIEs with empty suffix" do
      input = %(<http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> .)
      serialize(input, :standard_prefixes => true).
      should produce({
        CONTEXT=>{
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          COERCE  => {IRI=>"foaf:"}},
        SUBJECT   => "foaf:",
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
        CONTEXT   => {
          "db"    => "http://dbpedia.org/resource/",
          "dbo"   => "http://dbpedia.org/ontology/",
          COERCE  => {IRI=>"dbo:artistOf"}
        },
        SUBJECT   => "db:Michael_Jackson",
        "dbo:artistOf" => "db:%28I_Can%27t_Make_It%29_Another_Day"
      }, @debug)
    end

    it "should order literal values" do
      input = %(@base <http://a/> . <b> <c> "e", "d" .)
      serialize(input).
      should produce({
        SUBJECT       => "http://a/b",
        "http://a/c"  => ["d", "e"]
      }, @debug)
    end

    it "should order URI values" do
      input = %(@base <http://a/> . <b> <c> <e>, <d> .)
      serialize(input).
      should produce({
        CONTEXT       => {COERCE => {IRI => "http://a/c"}},
        SUBJECT       => "http://a/b",
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
        CONTEXT   => {
          ""      => "http://xmlns.com/foaf/0.1/",
          "dc"    => "http://purl.org/dc/elements/1.1/",
          "rdfs"  => "http://www.w3.org/2000/01/rdf-schema#",
          COERCE  => {IRI => ":c"}
        },
        SUBJECT       => ":b",
        TYPE          => ":class",
        "dc:title"    => "title",
        "rdfs:label"  => "label",
        ":c"          => ":d"
      }, @debug)
    end
    
    it "should generate object list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :b :c :d, :e .)
      serialize(input, :prefixes => {"" => RDF::FOAF}).
      should produce({
        CONTEXT => {
          ""=>"http://xmlns.com/foaf/0.1/",
          COERCE => {IRI=>":c"}},
        SUBJECT        => ":b",
        ":c"       => [":d", ":e"]
      }, @debug)
    end
    
    it "should generate property list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :b :c :d; :e :f .)
      serialize(input, :prefixes => {"" => RDF::FOAF}).
      should produce({
        CONTEXT => {
          ""      => "http://xmlns.com/foaf/0.1/",
          COERCE  => {IRI=>[":c", ":e"]}},
        SUBJECT   => ":b",
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
        CONTEXT     => {""=>"http://www.w3.org/2006/03/test-description#"},
        SUBJECT     => [
          {SUBJECT  => "test-cases/0001", TYPE => ":TestCase"},
          {SUBJECT  => "test-cases/0002", TYPE => ":TestCase"}
        ]
      }, @debug)
    end
  end
  
  context "literals" do
    it "coerces typed literal" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"^^ex:d .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        CONTEXT   => {
          "ex"    => "http://example.com/",
          COERCE  => {"ex:d" => "ex:b"}},
        SUBJECT   => "ex:a",
        "ex:b"    => "foo"
      }, @debug)
    end

    it "coerces integer" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1 .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        CONTEXT   => {
          "ex"    => "http://example.com/"},
        SUBJECT   => "ex:a",
        "ex:b"    => 1
      }, @debug)
    end

    it "coerces boolean" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b true .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        CONTEXT   => {
          "ex"    => "http://example.com/"},
        SUBJECT   => "ex:a",
        "ex:b"    => true
      }, @debug)
    end

    it "coerces decmal" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0 .)
      serialize(input, :prefixes => {:ex => "http://example.com/", :xsd => RDF::XSD}).should produce({
        CONTEXT   => {
          "ex"    => "http://example.com/",
          COERCE  => {"xsd:decimal" => "ex:b"}},
        SUBJECT   => "ex:a",
        "ex:b"    => "1.0"
      }, @debug)
    end

    it "coerces double" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0e0 .)
      serialize(input, :prefixes => {:ex => "http://example.com/", :xsd => RDF::XSD}).should produce({
        CONTEXT   => {
          "ex"    => "http://example.com/",
          COERCE  => {"xsd:double" => "ex:b"}},
        SUBJECT   => "ex:a",
        "ex:b"    => "1.0e0"
      }, @debug)
    end
    
    it "encodes language literal" do
      input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"@en-us .)
      serialize(input, :prefixes => {:ex => "http://example.com/"}).should produce({
        CONTEXT   => {
          "ex"    => "http://example.com/"},
        SUBJECT   => "ex:a",
        "ex:b"    => {LITERAL => "foo", LANGUAGE => "en-us"}
      }, @debug)
    end
  end

  context "anons" do
    it "should generate bare anon" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . [:a :b] .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          COERCE  => {IRI=>"foaf:a"}
        },
        "foaf:a"  => "foaf:b"
      }, @debug)
    end
    
    it "should generate anon as subject" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . [:a :b] :c :d .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          COERCE  => {IRI=>["foaf:a","foaf:c"]}
        },
        "foaf:a"  => "foaf:b",
        "foaf:c"  => "foaf:d"
      }, @debug)
    end
    
    it "should generate anon as object" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b [:c :d] .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          COERCE  => {IRI=>["foaf:b","foaf:c"]}
        },
        SUBJECT     => "foaf:a",
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
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        },
        SUBJECT => {LIST => [{SUBJECT => "foaf:a"}, {SUBJECT => "foaf:b"}]}
      }, @debug)
    end

    it "should generate literal list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b ( "apple" "banana" ) .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          COERCE  => {IRI=>"foaf:b"}
        },
        SUBJECT   => "foaf:a",
        "foaf:b"  => {LIST => ["apple", "banana"]}
      }, @debug)
    end
    
    it "should generate empty list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b () .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          COERCE  => {IRI=>"foaf:b"}
        },
        SUBJECT   => "foaf:a",
        "foaf:b"  => {LIST => []}
      }, @debug)
    end
    
    it "should generate single element list" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b ( "apple" ) .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          COERCE  => {IRI=>"foaf:b"}
        },
        SUBJECT   => "foaf:a",
        "foaf:b"  => {LIST => ["apple"]}
      }, @debug)
    end
    
    it "should generate single element list without @coerce" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b ( [ :b "foo" ] ) .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        },
        SUBJECT   => "foaf:a",
        "foaf:b"  => {"@list" => [{"foaf:b" => "foo"}]}
      }, @debug)
    end

    it "should generate empty list as subject" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . () :a :b .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          COERCE  => {IRI=>"foaf:a"}
        },
        SUBJECT   => {LIST => []},
        "foaf:a"  => "foaf:b"
      }, @debug)
    end
    
    it "should generate list as subject" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . (:a) :b :c .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          COERCE  => {IRI=>"foaf:b"}
        },
        SUBJECT   => {LIST => [{SUBJECT => "foaf:a"}]},
        "foaf:b"  => "foaf:c"
      }, @debug)
    end

    it "should generate list of lists" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :listOf2Lists = (() (1)) .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "owl"   => "http://www.w3.org/2002/07/owl#",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          COERCE  => {IRI=>"owl:sameAs"}
        },
        SUBJECT       => "foaf:listOf2Lists",
        "owl:sameAs"  => {LIST => [
          {LIST => []},
          {LIST => [1]}
        ]}
      }, @debug)
    end
    
    it "should generate list anon" do
      input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :twoAnons = ([a :mother] [a :father]) .)
      serialize(input, :standard_prefixes => true).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "owl"   => "http://www.w3.org/2002/07/owl#",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          COERCE  => {IRI=>"owl:sameAs"}
        },
        SUBJECT       => "foaf:twoAnons",
        "owl:sameAs"  => {LIST => [
          {TYPE => "foaf:mother"},
          {TYPE => "foaf:father"}
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
      serialize(input, :coerce => {RDF::OWL.unionOf.to_s => IRI}, :standard_prefixes => true ).should produce({
        CONTEXT   => {
          "foaf"  => "http://xmlns.com/foaf/0.1/",
          "owl"   => "http://www.w3.org/2002/07/owl#",
          "rdf"   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
          "rdfs"  => "http://www.w3.org/2000/01/rdf-schema#",
          COERCE  => {IRI=>["rdfs:domain", "owl:unionOf"]}
        },
        SUBJECT         => "foaf:a",
        "rdfs:domain"   => {
          TYPE          => "owl:Class",
          "owl:unionOf" => {LIST => ["foaf:b", "foaf:c"]}
        }
      }, @debug)
    end
  end

  context "context" do
    context "base" do
      it "shortens URIs" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        serialize(input, :base_uri => "http://a/").should produce({
          CONTEXT       => {
            BASE        => "http://a/",
            COERCE      => {IRI => "http://a/c"}},
          SUBJECT       => "b",
          "http://a/c"  => "d"
        }, @debug)
      end
    end
    
    context "vocab" do
      it "shortens URIs" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        serialize(input, :vocab => "http://a/").should produce({
          CONTEXT   => {
            VOCAB   => "http://a/",
            COERCE  => {IRI => "c"}},
          SUBJECT   => "http://a/b",
          "c"       => "http://a/d"
        }, @debug)
      end
    end
    
    context "coerce" do
      it "does not coerce properties with hetrogeneous types" do
        input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b :c, "d" .)
        serialize(input, :standard_prefixes => true).should produce({
          CONTEXT   => {"foaf"  => "http://xmlns.com/foaf/0.1/"},
          SUBJECT   => "foaf:a",
          "foaf:b"  => ["d", {IRI=>"foaf:c"}]
        }, @debug)
      end
      
      it "does not coerce properties with hetgogeneous literal datatype" do
        input = %(@prefix : <http://xmlns.com/foaf/0.1/> . :a :b "c", "d"@en, "f"^^:g .)
        serialize(input, :standard_prefixes => true).should produce({
          CONTEXT   => {"foaf"  => "http://xmlns.com/foaf/0.1/"},
          SUBJECT   => "foaf:a",
          "foaf:b"  => ["c", {LITERAL => "d", LANGUAGE => "en"}, {LITERAL => "f", DATATYPE => "foaf:g"}]
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
    RDF::Graph.new << RDF::N3::Reader.new(input, options)
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
