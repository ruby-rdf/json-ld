# frozen_string_literal: true

require_relative 'spec_helper'

describe JSON::LD::API do
  let(:logger) { RDF::Spec.logger }

  describe ".frame" do
    {
      'exact @type match': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1"
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }]
        })
      },
      'wildcard @type match': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": {}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }]
        })
      },
      'match none @type match': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": []
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:p": "Foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:p": "Bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub2",
            "ex:p": "Bar"
          }]
        })
      },
      'multiple matches on @type': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1"
        }),
        input: %([{
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1"
        }, {
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub2",
          "@type": "ex:Type1"
        }, {
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub3",
          "@type": ["ex:Type1", "ex:Type2"]
        }]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub2",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub3",
            "@type": ["ex:Type1", "ex:Type2"]
          }]
        })
      },
      'single @id match': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1"
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }]
        })
      },
      'multiple @id match': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": ["ex:Sub1", "ex:Sub2"]
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "@type": "ex:Type3"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }]
        })
      },
      'wildcard and match none': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:p": [],
          "ex:q": {}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:p": "foo",
            "ex:q": "bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": null,
            "ex:q": "bar"
          }]
        })
      },
      'match on any property if @requireAll is false': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": false,
          "ex:p": {},
          "ex:q": {}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:q": "bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "foo",
            "ex:q": null
          }, {
            "@id": "ex:Sub2",
            "ex:p": null,
            "ex:q": "bar"
          }]
        })
      },
      'match on defeaults if @requireAll is true and at least one property matches': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": true,
          "ex:p": {"@default": "Foo"},
          "ex:q": {"@default": "Bar"}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub4",
            "ex:r": "baz"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "foo",
            "ex:q": "Bar"
          }, {
            "@id": "ex:Sub2",
            "ex:p": "Foo",
            "ex:q": "bar"
          }, {
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }]
        })
      },
      'match with @requireAll with one default': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": true,
          "ex:p": {},
          "ex:q": {"@default": "Bar"}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "foo",
            "ex:q": "Bar"
          }, {
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }]
        })
      },
      "don't match with @requireAll, matching @type but no matching property": {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": true,
          "@type": "ex:Type",
          "ex:p": {}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "ex:p": "foo"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type",
            "ex:p": "foo"
          }]
        })
      },
      "don't match with @requireAll, matching @id but no matching @type": {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": true,
          "@id": ["ex:Sub1", "ex:Sub2"],
          "@type": "ex:Type"
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:OtherType"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "@type": "ex:Type",
            "ex:p": "foo"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type",
            "ex:p": "foo"
          }]
        })
      },
      'issue #40 - example': {
        frame: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "https://schema.org/"
          },
          "@type": "Person",
          "@requireAll": true,
          "givenName": "John",
          "familyName": "Doe"
        }),
        input: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "https://schema.org/"
          },
          "@graph": [
            {
              "@id": "1",
              "@type": "Person",
              "name": "John Doe",
              "givenName": "John",
              "familyName": "Doe"
            },
            {
              "@id": "2",
              "@type": "Person",
              "name": "Jane Doe",
              "givenName": "Jane"
            }
          ]
        }),
        output: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "https://schema.org/"
          },
          "@id": "1",
          "@type": "Person",
          "familyName": "Doe",
          "givenName": "John",
          "name": "John Doe"
        }),
        processingMode: 'json-ld-1.1'
      },
      'implicitly includes unframed properties (default @explicit false)': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1"
        }),
        input: '{
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }',
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {"@id": "ex:Obj1"}
          }]
        })
      },
      'explicitly includes unframed properties @explicit false': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@explicit": false,
          "@type": "ex:Type1"
        }),
        input: '{
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }',
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {"@id": "ex:Obj1"}
          }]
        })
      },
      'explicitly excludes unframed properties (@explicit: true)': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@explicit": true,
          "@type": "ex:Type1"
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }]
        })
      },
      'non-existent framed properties create null property': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1",
          "ex:null": []
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {
            "ex": "http://example.org/"
          },
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {
              "@id": "ex:Obj1"
            },
            "ex:null": null
          }]
        })
      },
      'non-existent framed properties create default property': {
        frame: %({
          "@context": {
            "ex": "http://example.org/",
            "ex:null": {"@container": "@set"}
          },
          "@type": "ex:Type1",
          "ex:null": [{"@default": "foo"}]
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {
            "ex": "http://example.org/",
            "ex:null": {"@container": "@set"}
          },
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {"@id": "ex:Obj1"},
            "ex:null": ["foo"]
          }]
        })
      },
      'default value for @type': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": {"@default": "ex:Foo"},
          "ex:foo": "bar"
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:foo": "bar"
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Foo",
            "ex:foo": "bar"
          }]
        })
      },
      'mixed content': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:mixed": {"@embed": "@never"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:mixed": [
            {"@id": "ex:Sub2"},
            "literal1"
          ]
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:mixed": [
              {"@id": "ex:Sub2"},
              "literal1"
            ]
          }]
        })
      },
      'no embedding (@embed: @never)': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:embed": {"@embed": "@never"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:embed": {
            "@id": "ex:Sub2",
            "ex:prop": "property"
          }
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:embed": {"@id": "ex:Sub2"}
          }]
        })
      },
      'first embed (@embed: @once)': {
        frame: %({
          "@context": {"ex": "http://www.example.com/#"},
          "@type": "ex:Thing",
          "@embed": "@once"
        }),
        input: %({
          "@context": {"ex": "http://www.example.com/#"},
          "@id": "http://example/outer",
          "@type": "ex:Thing",
          "ex:embed1": {"@id": "http://example/embedded", "ex:name": "Embedded"},
          "ex:embed2": {"@id": "http://example/embedded", "ex:name": "Embedded"}
        }),
        output: %({
          "@context": {"ex": "http://www.example.com/#"},
          "@graph": [
            {
              "@id": "http://example/outer",
              "@type": "ex:Thing",
              "ex:embed1": {"@id": "http://example/embedded", "ex:name": "Embedded"},
              "ex:embed2": {"@id": "http://example/embedded"}
            }
          ]
        }),
        ordered: true
      },
      'always embed (@embed: @always)': {
        frame: %({
          "@context": {"ex": "http://www.example.com/#"},
          "@type": "ex:Thing",
          "@embed": "@always"
        }),
        input: %({
          "@context": {"ex": "http://www.example.com/#"},
          "@id": "http://example/outer",
          "@type": "ex:Thing",
          "ex:embed1": {"@id": "http://example/embedded", "ex:name": "Embedded"},
          "ex:embed2": {"@id": "http://example/embedded", "ex:name": "Embedded"}
        }),
        output: %({
          "@context": {"ex": "http://www.example.com/#"},
          "@graph": [
            {
              "@id": "http://example/outer",
              "@type": "ex:Thing",
              "ex:embed1": {"@id": "http://example/embedded", "ex:name": "Embedded"},
              "ex:embed2": {"@id": "http://example/embedded", "ex:name": "Embedded"}
            }
          ]
        })
      },
      'mixed list': {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:mixedlist": {}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:mixedlist": {
            "@list": [
              {"@id": "ex:Sub2", "@type": "ex:Type2"},
              "literal1"
            ]
          }
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:mixedlist": {
              "@list": [
                {"@id": "ex:Sub2", "@type": "ex:Type2"},
                "literal1"
              ]
            }
          }]
        })
      },
      'framed list': {
        frame: %({
          "@context": {
            "ex": "http://example.org/",
            "list": {"@id": "ex:list", "@container": "@list"}
          },
          "list": [{"@type": "ex:Element"}]
        }),
        input: %({
          "@context": {
            "ex": "http://example.org/",
            "list": {"@id": "ex:list", "@container": "@list"}
          },
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "list": [
            {"@id": "ex:Sub2", "@type": "ex:Element"},
            "literal1"
          ]
        }),
        output: %({
          "@context": {
            "ex": "http://example.org/",
            "list": {"@id": "ex:list", "@container": "@list"}
          },
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "list": [
              {"@id": "ex:Sub2", "@type": "ex:Element"},
              "literal1"
            ]
          }]
        })
      },
      'presentation example': {
        frame: %({
          "@context": {
            "primaryTopic": {
              "@id": "http://xmlns.com/foaf/0.1/primaryTopic",
              "@type": "@id"
            },
            "sameAs": {
              "@id": "http://www.w3.org/2002/07/owl#sameAs",
              "@type": "@id"
            }
          },
          "primaryTopic": {
            "@type": "http://dbpedia.org/class/yago/Buzzwords",
            "sameAs": {}
          }
        }),
        input: %([{
          "@id": "http://en.wikipedia.org/wiki/Linked_Data",
          "http://xmlns.com/foaf/0.1/primaryTopic": {"@id": "http://dbpedia.org/resource/Linked_Data"}
        }, {
          "@id": "http://www4.wiwiss.fu-berlin.de/flickrwrappr/photos/Linked_Data",
          "http://www.w3.org/2002/07/owl#sameAs": {"@id": "http://dbpedia.org/resource/Linked_Data"}
        }, {
          "@id": "http://dbpedia.org/resource/Linked_Data",
          "@type": "http://dbpedia.org/class/yago/Buzzwords",
          "http://www.w3.org/2002/07/owl#sameAs": {"@id": "http://rdf.freebase.com/ns/m/02r2kb1"}
        }, {
          "@id": "http://mpii.de/yago/resource/Linked_Data",
          "http://www.w3.org/2002/07/owl#sameAs": {"@id": "http://dbpedia.org/resource/Linked_Data"}
        }
      ]),
        output: %({
          "@context": {
            "primaryTopic": {"@id": "http://xmlns.com/foaf/0.1/primaryTopic", "@type": "@id"},
            "sameAs": {"@id": "http://www.w3.org/2002/07/owl#sameAs", "@type": "@id"}
          },
          "@graph": [{
            "@id": "http://en.wikipedia.org/wiki/Linked_Data",
            "primaryTopic": {
              "@id": "http://dbpedia.org/resource/Linked_Data",
              "@type": "http://dbpedia.org/class/yago/Buzzwords",
              "sameAs": "http://rdf.freebase.com/ns/m/02r2kb1"
            }
          }]
        })
      },
      'microdata manifest': {
        frame: %({
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "mf": "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq": "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "comment": "rdfs:comment",
            "entries": {"@id": "mf:entries", "@container": "@list"},
            "name": "mf:name",
            "action": "mf:action",
            "data": {"@id": "mq:data", "@type": "@id"},
            "query": {"@id": "mq:query", "@type": "@id"},
            "result": {"@id": "mf:result", "@type": "xsd:boolean"}
          },
          "@type": "mf:Manifest",
          "entries": [{
            "@type": "mf:ManifestEntry",
            "action": {
              "@type": "mq:QueryTest"
            }
          }]
        }),
        input: '{
          "@context": {
            "md": "http://www.w3.org/ns/md#",
            "mf": "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq": "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#"
          },
          "@graph": [{
            "@id": "_:manifest",
            "@type": "mf:Manifest",
            "mf:entries": {"@list": [{"@id": "_:entry"}]},
            "rdfs:comment": "Positive processor tests"
          }, {
            "@id": "_:entry",
            "@type": "mf:ManifestEntry",
            "mf:action": {"@id": "_:query"},
            "mf:name": "Test 0001",
            "mf:result": "true",
            "rdfs:comment": "Item with no itemtype and literal itemprop"
          }, {
            "@id": "_:query",
            "@type": "mq:QueryTest",
            "mq:data": {"@id": "http://www.w3.org/TR/microdata-rdf/tests/0001.html"},
            "mq:query": {"@id": "http://www.w3.org/TR/microdata-rdf/tests/0001.ttl"}
          }]
        }',
        output: %({
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "mf": "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq": "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "comment": "rdfs:comment",
            "entries": {"@id": "mf:entries","@container": "@list"},
            "name": "mf:name",
            "action": "mf:action",
            "data": {"@id": "mq:data", "@type": "@id"},
            "query": {"@id": "mq:query", "@type": "@id"},
            "result": {"@id": "mf:result", "@type": "xsd:boolean"}
          },
          "@type": "mf:Manifest",
          "comment": "Positive processor tests",
          "entries": [{
            "@type": "mf:ManifestEntry",
            "action": {
              "@type": "mq:QueryTest",
              "data": "http://www.w3.org/TR/microdata-rdf/tests/0001.html",
              "query": "http://www.w3.org/TR/microdata-rdf/tests/0001.ttl"
            },
            "comment": "Item with no itemtype and literal itemprop",
            "mf:result": "true",
            "name": "Test 0001"
          }]
        }),
        processingMode: 'json-ld-1.1'
      },
      library: {
        frame: %({
          "@context": {
            "dc": "http://purl.org/dc/elements/1.1/",
            "ex": "http://example.org/vocab#",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "ex:contains": { "@type": "@id" }
          },
          "@type": "ex:Library",
          "ex:contains": {}
        }),
        input: %({
          "@context": {
            "dc": "http://purl.org/dc/elements/1.1/",
            "ex": "http://example.org/vocab#",
            "xsd": "http://www.w3.org/2001/XMLSchema#"
          },
          "@id": "http://example.org/library",
          "@type": "ex:Library",
          "dc:name": "Library",
          "ex:contains": {
            "@id": "http://example.org/library/the-republic",
            "@type": "ex:Book",
            "dc:creator": "Plato",
            "dc:title": "The Republic",
            "ex:contains": {
              "@id": "http://example.org/library/the-republic#introduction",
              "@type": "ex:Chapter",
              "dc:description": "An introductory chapter on The Republic.",
              "dc:title": "The Introduction"
            }
          }
        }),
        output: %({
          "@context": {
            "dc": "http://purl.org/dc/elements/1.1/",
            "ex": "http://example.org/vocab#",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "ex:contains": { "@type": "@id" }
          },
          "@graph": [
            {
              "@id": "http://example.org/library",
              "@type": "ex:Library",
              "dc:name": "Library",
              "ex:contains": {
                "@id": "http://example.org/library/the-republic",
                "@type": "ex:Book",
                "dc:creator": "Plato",
                "dc:title": "The Republic",
                "ex:contains": {
                  "@id": "http://example.org/library/the-republic#introduction",
                  "@type": "ex:Chapter",
                  "dc:description": "An introductory chapter on The Republic.",
                  "dc:title": "The Introduction"
                }
              }
            }
          ]
        })
      }
    }.each do |title, params|
      it title do
        do_frame(params)
      end
    end

    describe "@reverse" do
      {
        'embed matched frames with @reverse': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "@type": "ex:Type1",
            "@reverse": {"ex:includes": {}}
          }),
          input: %([{
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2",
            "ex:includes": {"@id": "ex:Sub1"}
          }]),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "@reverse": {
                "ex:includes": {
                  "@id": "ex:Sub2",
                  "@type": "ex:Type2",
                  "ex:includes": {
                    "@id": "ex:Sub1"
                  }
                }
              }
            }]
          })
        },
        'embed matched frames with reversed property': {
          frame: %({
            "@context": {
              "ex": "http://example.org/",
              "excludes": {"@reverse": "ex:includes"}
            },
            "@type": "ex:Type1",
            "excludes": {}
          }),
          input: %([{
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2",
            "ex:includes": {"@id": "ex:Sub1"}
          }]),
          output: %({
            "@context": {
              "ex": "http://example.org/",
              "excludes": {"@reverse": "ex:includes"}
            },
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "excludes": {
                "@id": "ex:Sub2",
                "@type": "ex:Type2",
                "ex:includes": {"@id": "ex:Sub1"}
              }
            }]
          })
        }
      }.each do |title, params|
        it title do
          do_frame(params)
        end
      end
    end

    context "omitGraph option" do
      {
        'Defaults to false in 1.0': {
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }]),
          frame: %({
            "@context": {
              "@vocab": "http://example.org/"
            }
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/"
            },
            "@graph": [{
              "foo": "bar",
              "prop": "value"
            }]
          }),
          processingMode: "json-ld-1.0"
        },
        'Set with option in 1.0': {
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }]),
          frame: %({
            "@context": {
              "@vocab": "http://example.org/"
            }
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/"
            },
            "foo": "bar",
            "prop": "value"
          }),
          processingMode: "json-ld-1.0",
          omitGraph: true
        },
        'Defaults to true in 1.1': {
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }]),
          frame: %({
            "@context": {
              "@vocab": "http://example.org/"
            }
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/"
            },
            "foo": "bar",
            "prop": "value"
          }),
          processingMode: "json-ld-1.1"
        },
        'Set with option in 1.1': {
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }]),
          frame: %({
            "@context": {
              "@vocab": "http://example.org/"
            }
          }),
          output: %({
            "@context": {
              "@vocab": "http://example.org/"
            },
            "@graph": [{
              "foo": "bar",
              "prop": "value"
            }]
          }),
          processingMode: "json-ld-1.1",
          omitGraph: false
        }
      }.each do |title, params|
        it(title) { do_frame(params.merge(pruneBlankNodeIdentifiers: true)) }
      end
    end

    context "@included" do
      {
        'Basic Included array': {
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }, {
            "http://example.org/prop": [{"@value": "value2"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }]),
          frame: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/",
              "included": {"@id": "@included", "@container": "@set"}
            },
            "@requireAll": true,
            "foo": "bar",
            "prop": "value",
            "@included": [{
              "@requireAll": true,
              "foo": "bar",
              "prop": "value2"
            }]
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/",
              "included": {"@id": "@included", "@container": "@set"}
            },
            "foo": "bar",
            "included": [{
              "foo": "bar",
              "prop": "value2"
            }],
            "prop": "value"
          })
        },
        'Basic Included object': {
          input: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }, {
            "http://example.org/prop": [{"@value": "value2"}],
            "http://example.org/foo": [{"@value": "bar"}]
          }]),
          frame: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "@requireAll": true,
            "foo": "bar",
            "prop": "value",
            "@included": [{
              "@requireAll": true,
              "foo": "bar",
              "prop": "value2"
            }]
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "foo": "bar",
            "prop": "value",
            "@included": {
              "prop": "value2",
              "foo": "bar"
            }
          })
        },
        'json.api example': {
          input: %([{
            "@id": "http://example.org/base/1",
            "@type": ["http://example.org/vocab#articles"],
            "http://example.org/vocab#title": [{"@value": "JSON:API paints my bikeshed!"}],
            "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1"}],
            "http://example.org/vocab#author": [{
              "@id": "http://example.org/base/9",
              "@type": ["http://example.org/vocab#people"],
              "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1/relationships/author"}],
              "http://example.org/vocab#related": [{"@id": "http://example.com/articles/1/author"}]
            }],
            "http://example.org/vocab#comments": [{
              "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1/relationships/comments"}],
              "http://example.org/vocab#related": [{"@id": "http://example.com/articles/1/comments"}]
            }],
            "@included": [{
              "@id": "http://example.org/base/9",
              "@type": ["http://example.org/vocab#people"],
              "http://example.org/vocab#first-name": [{"@value": "Dan"}],
              "http://example.org/vocab#last-name": [{"@value": "Gebhardt"}],
              "http://example.org/vocab#twitter": [{"@value": "dgeb"}],
              "http://example.org/vocab#self": [{"@id": "http://example.com/people/9"}]
            }, {
              "@id": "http://example.org/base/5",
              "@type": ["http://example.org/vocab#comments"],
              "http://example.org/vocab#body": [{"@value": "First!"}],
              "http://example.org/vocab#author": [{
                "@id": "http://example.org/base/2",
                "@type": ["http://example.org/vocab#people"]
              }],
              "http://example.org/vocab#self": [{"@id": "http://example.com/comments/5"}]
            }, {
              "@id": "http://example.org/base/12",
              "@type": ["http://example.org/vocab#comments"],
              "http://example.org/vocab#body": [{"@value": "I like XML better"}],
              "http://example.org/vocab#author": [{
                "@id": "http://example.org/base/9",
                "@type": ["http://example.org/vocab#people"]
              }],
              "http://example.org/vocab#self": [{"@id": "http://example.com/comments/12"}]
            }]
          }]),
          frame: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/vocab#",
              "@base": "http://example.org/base/",
              "id": "@id",
              "type": "@type",
              "data": "@nest",
              "attributes": "@nest",
              "links": "@nest",
              "relationships": "@nest",
              "included": "@included",
              "author": {"@type": "@id"},
              "self": {"@type": "@id"},
              "related": {"@type": "@id"},
              "comments": {"@context": {"data": null}}
            },
            "data": {"type": "articles"},
            "included": {
              "@requireAll": true,
              "type": ["comments", "people"],
              "self": {}
            }
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/vocab#",
              "@base": "http://example.org/base/",
              "id": "@id",
              "type": "@type",
              "data": "@nest",
              "attributes": "@nest",
              "links": "@nest",
              "relationships": "@nest",
              "included": "@included",
              "author": {"@type": "@id"},
              "self": {"@type": "@id"},
              "related": {"@type": "@id"},
              "comments": {"@context": {"data": null}}
            },
            "id": "1",
            "type": "articles",
            "title": "JSON:API paints my bikeshed!",
            "self": "http://example.com/articles/1",
            "author": "9",
            "comments": {
              "self": "http://example.com/articles/1/relationships/comments",
              "related": "http://example.com/articles/1/comments"
            },
            "included": [{
              "id": "5",
              "type": "comments",
              "body": "First!",
              "author": {"id": "2", "type": "people"},
              "self": "http://example.com/comments/5"
            }, {
              "id": "9",
              "type": "people",
              "first-name": "Dan",
              "last-name": "Gebhardt",
              "twitter": "dgeb",
              "self": [
                "http://example.com/people/9",
                "http://example.com/articles/1/relationships/author"
              ],
              "related": "http://example.com/articles/1/author"
            }, {
              "id": "12",
              "type": "comments",
              "body": "I like XML better",
              "author": "9",
              "self": "http://example.com/comments/12"
            }]
          })
        }
      }.each do |title, params|
        it(title) { do_frame(params.merge(processingMode: 'json-ld-1.1')) }
      end
    end

    describe "node pattern" do
      {
        'matches a deep node pattern': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": {
              "ex:q": {}
            }
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "ex:p": {
                "@id": "ex:Sub2",
                "@type": "ex:Type2",
                "ex:q": "foo"
              }
            }, {
              "@id": "ex:Sub3",
              "@type": "ex:Type1",
              "ex:q": {
                "@id": "ex:Sub4",
                "@type": "ex:Type2",
                "ex:r": "bar"
              }
            }]
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "ex:p": {
                "@id": "ex:Sub2",
                "@type": "ex:Type2",
                "ex:q": "foo"
              }
            }]
          })
        }
      }.each do |title, params|
        it title do
          do_frame(params)
        end
      end
    end

    describe "value pattern" do
      {
        'matches exact values': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:p": "P",
              "ex:q": {"@value": "Q", "@type": "ex:q"},
              "ex:r": {"@value": "R", "@language": "r"}
            }]
          })
        },
        'matches wildcard @value': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": {"@value": {}},
            "ex:q": {"@value": {}, "@type": "ex:q"},
            "ex:r": {"@value": {}, "@language": "r"}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:p": "P",
              "ex:q": {"@value": "Q", "@type": "ex:q"},
              "ex:r": {"@value": "R", "@language": "r"}
            }]
          })
        },
        'matches wildcard @type': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:q": {"@value": "Q", "@type": {}}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:q": {"@value": "Q", "@type": "ex:q"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:q": {"@value": "Q", "@type": "ex:q"}
            }]
          })
        },
        'matches wildcard @language': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:r": {"@value": "R", "@language": {}}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:r": {"@value": "R", "@language": "r"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:r": {"@value": "R", "@language": "r"}
            }]
          })
        },
        'match none @type': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": {"@value": {}, "@type": []},
            "ex:q": {"@value": {}, "@type": "ex:q"},
            "ex:r": {"@value": {}, "@language": "r"}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:p": "P",
              "ex:q": {"@value": "Q", "@type": "ex:q"},
              "ex:r": {"@value": "R", "@language": "r"}
            }]
          })
        },
        'match none @language': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": {"@value": {}, "@language": []},
            "ex:q": {"@value": {}, "@type": "ex:q"},
            "ex:r": {"@value": {}, "@language": "r"}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:p": "P",
              "ex:q": {"@value": "Q", "@type": "ex:q"},
              "ex:r": {"@value": "R", "@language": "r"}
            }]
          })
        },
        'matches some @value': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": {"@value": ["P", "Q", "R"]},
            "ex:q": {"@value": ["P", "Q", "R"], "@type": "ex:q"},
            "ex:r": {"@value": ["P", "Q", "R"], "@language": "r"}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:p": "P",
              "ex:q": {"@value": "Q", "@type": "ex:q"},
              "ex:r": {"@value": "R", "@language": "r"}
            }]
          })
        },
        'matches some @type': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:q": {"@value": "Q", "@type": ["ex:q", "ex:Q"]}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:q": {"@value": "Q", "@type": "ex:q"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:q": {"@value": "Q", "@type": "ex:q"}
            }]
          })
        },
        'matches some @language': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:r": {"@value": "R", "@language": ["p", "q", "r"]}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:r": {"@value": "R", "@language": "R"}
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:r": {"@value": "R", "@language": "R"}
            }]
          })
        },
        'excludes non-matched values': {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": {"@value": {}},
            "ex:q": {"@value": {}, "@type": "ex:q"},
            "ex:r": {"@value": {}, "@language": "R"}
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": ["P", {"@value": "P", "@type": "ex:p"}, {"@value": "P", "@language": "P"}],
            "ex:q": ["Q", {"@value": "Q", "@type": "ex:q"}, {"@value": "Q", "@language": "Q"}],
            "ex:r": ["R", {"@value": "R", "@type": "ex:r"}, {"@value": "R", "@language": "R"}]
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "ex:p": "P",
              "ex:q": {"@value": "Q", "@type": "ex:q"},
              "ex:r": {"@value": "R", "@language": "R"}
            }]
          })
        }
      }.each do |title, params|
        it title do
          do_frame(params)
        end
      end
    end

    describe "named graphs" do
      {
        'Merge graphs if no outer @graph is used': {
          frame: %({
            "@context": {"@vocab": "urn:"},
            "@type": "Class"
          }),
          input: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "preserve": {
              "@graph": {
                "@id": "urn:id-2",
                "term": "data"
              }
            }
          }),
          output: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "preserve": {}
          }),
          processingMode: 'json-ld-1.1'
        },
        'Frame default graph if outer @graph is used': {
          frame: %({
            "@context": {"@vocab": "urn:"},
            "@type": "Class",
            "@graph": {}
          }),
          input: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "preserve": {
              "@id": "urn:gr-1",
              "@graph": {
                "@id": "urn:id-2",
                "term": "data"
              }
            }
          }),
          output: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "preserve": {
              "@id": "urn:gr-1",
              "@graph": {
                "@id": "urn:id-2",
                "term": "data"
              }
            }
          }),
          processingMode: 'json-ld-1.1'
        },
        'Merge one graph and preserve another': {
          frame: %({
            "@context": {"@vocab": "urn:"},
            "@type": "Class",
            "preserve": {
              "@graph": {}
            }
          }),
          input: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "merge": {
              "@id": "urn:id-2",
              "@graph": {
                "@id": "urn:id-2",
                "term": "foo"
              }
            },
            "preserve": {
              "@id": "urn:graph-1",
              "@graph": {
                "@id": "urn:id-3",
                "term": "bar"
              }
            }
          }),
          output: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "merge": {
              "@id": "urn:id-2",
              "term": "foo"
            },
            "preserve": {
              "@id": "urn:graph-1",
              "@graph": {
                "@id": "urn:id-3",
                "term": "bar"
              }
            }
          }),
          processingMode: 'json-ld-1.1'
        },
        'Merge one graph and deep preserve another': {
          frame: %({
            "@context": {"@vocab": "urn:"},
            "@type": "Class",
            "preserve": {
              "deep": {
                "@graph": {}
              }
            }
          }),
          input: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "merge": {
              "@id": "urn:id-2",
              "@graph": {
                "@id": "urn:id-2",
                "term": "foo"
              }
            },
            "preserve": {
              "deep": {
                "@graph": {
                  "@id": "urn:id-3",
                  "term": "bar"
                }
              }
            }
          }),
          output: %({
            "@context": {"@vocab": "urn:"},
            "@id": "urn:id-1",
            "@type": "Class",
            "merge": {
              "@id": "urn:id-2",
              "term": "foo"
            },
            "preserve": {
              "deep": {
                "@graph": {
                  "@id": "urn:id-3",
                  "term": "bar"
                }
              }
            }
          }),
          processingMode: 'json-ld-1.1'
        },
        library: {
          frame: %({
            "@context": {"@vocab": "http://example.org/"},
            "@type": "Library",
            "contains": {
              "@id": "http://example.org/graphs/books",
              "@graph": {"@type": "Book"}
            }
          }),
          input: %({
            "@context": {"@vocab": "http://example.org/"},
            "@id": "http://example.org/library",
            "@type": "Library",
            "name": "Library",
            "contains": {
              "@id": "http://example.org/graphs/books",
              "@graph": {
                "@id": "http://example.org/library/the-republic",
                "@type": "Book",
                "creator": "Plato",
                "title": "The Republic",
                "contains": {
                  "@id": "http://example.org/library/the-republic#introduction",
                  "@type": "Chapter",
                  "description": "An introductory chapter on The Republic.",
                  "title": "The Introduction"
                }
              }
            }
          }),
          output: %({
            "@context": {"@vocab": "http://example.org/"},
            "@id": "http://example.org/library",
            "@type": "Library",
            "name": "Library",
            "contains": {
              "@id": "http://example.org/graphs/books",
              "@graph": {
                "@id": "http://example.org/library/the-republic",
                "@type": "Book",
                "creator": "Plato",
                "title": "The Republic",
                "contains": {
                  "@id": "http://example.org/library/the-republic#introduction",
                  "@type": "Chapter",
                  "description": "An introductory chapter on The Republic.",
                  "title": "The Introduction"
                }
              }
            }
          }),
          processingMode: 'json-ld-1.1'
        },
        'named graph with @embed: @never': {
          input: %({
            "@id": "ex:cred",
            "ex:subject": {
              "@id": "ex:Subject",
              "ex:name": "the subject"
            },
            "ex:proof": {
              "@graph": {
                "@type": "ex:Proof",
                "ex:name": "the proof",
                "ex:signer": [{
                  "@id": "ex:Subject",
                  "ex:name": "something different"
                }]
              }
            }
          }),
          frame: %({
            "@context": {
              "@version": 1.1,
              "proof": {"@id": "ex:proof", "@container": "@graph"}
            },
            "@graph": {
              "proof": {"@embed": "@never"}
            }
          }),
          output: %({
            "@context": {
              "@version": 1.1,
              "proof": {
                "@id": "ex:proof",
                "@container": "@graph"
              }
            },
            "@id": "ex:cred",
            "ex:subject": {
              "@id": "ex:Subject",
              "ex:name": "the subject"
            },
            "proof": {
              "@included": [
                {
                  "@type": "ex:Proof",
                  "ex:name": "the proof",
                  "ex:signer": {
                    "@id": "ex:Subject"
                  }
                },
                {
                  "@id": "ex:Subject",
                  "ex:name": "something different"
                }
              ]
            }
          }),
          processingMode: 'json-ld-1.1'
        }
      }.each do |title, params|
        it title do
          do_frame(params)
        end
      end
    end
  end

  describe "prune blank nodes" do
    {
      'preserves single-use bnode identifiers if @version 1.0': {
        frame: %({
          "@context": {
            "dc": "http://purl.org/dc/terms/",
            "dc:creator": {
              "@type": "@id"
            },
            "foaf": "http://xmlns.com/foaf/0.1/",
            "ps": "http://purl.org/payswarm#"
          },
          "@id": "http://example.com/asset",
          "@type": "ps:Asset",
          "dc:creator": {}
        }),
        input: %({
          "@context": {
            "dc": "http://purl.org/dc/terms/",
            "dc:creator": {
              "@type": "@id"
            },
            "foaf": "http://xmlns.com/foaf/0.1/",
            "ps": "http://purl.org/payswarm#"
          },
          "@id": "http://example.com/asset",
          "@type": "ps:Asset",
          "dc:creator": {
            "foaf:name": "John Doe"
          }
        }),
        output: %({
          "@context": {
            "dc": "http://purl.org/dc/terms/",
            "dc:creator": {
              "@type": "@id"
            },
            "foaf": "http://xmlns.com/foaf/0.1/",
            "ps": "http://purl.org/payswarm#"
          },
          "@graph": [
            {
              "@id": "http://example.com/asset",
              "@type": "ps:Asset",
              "dc:creator": {
                "@id": "_:b0",
                "foaf:name": "John Doe"
              }
            }
          ]
        }),
        processingMode: 'json-ld-1.0'
      },
      'preserves single-use bnode identifiers if pruneBlankNodeIdentifiers=false': {
        frame: %({
          "@context": {
            "dc": "http://purl.org/dc/terms/",
            "dc:creator": {
              "@type": "@id"
            },
            "foaf": "http://xmlns.com/foaf/0.1/",
            "ps": "http://purl.org/payswarm#"
          },
          "@id": "http://example.com/asset",
          "@type": "ps:Asset",
          "dc:creator": {}
        }),
        input: %({
          "@context": {
            "dc": "http://purl.org/dc/terms/",
            "dc:creator": {
              "@type": "@id"
            },
            "foaf": "http://xmlns.com/foaf/0.1/",
            "ps": "http://purl.org/payswarm#"
          },
          "@id": "http://example.com/asset",
          "@type": "ps:Asset",
          "dc:creator": {
            "foaf:name": "John Doe"
          }
        }),
        output: %({
          "@context": {
            "dc": "http://purl.org/dc/terms/",
            "dc:creator": {
              "@type": "@id"
            },
            "foaf": "http://xmlns.com/foaf/0.1/",
            "ps": "http://purl.org/payswarm#"
          },
          "@graph": [
            {
              "@id": "http://example.com/asset",
              "@type": "ps:Asset",
              "dc:creator": {
                "@id": "_:b0",
                "foaf:name": "John Doe"
              }
            }
          ]
        }),
        pruneBlankNodeIdentiers: false
      },
      'framing with @version: 1.1 prunes identifiers': {
        frame: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "https://example.com#",
            "ex": "http://example.org/",
            "claim": {
              "@id": "ex:claim",
              "@container": "@graph"
            },
            "id": "@id"
          },
          "claim": {}
        }),
        input: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "https://example.com#",
            "ex": "http://example.org/",
            "claim": {
              "@id": "ex:claim",
              "@container": "@graph"
            },
            "id": "@id"
          },
          "claim": {
            "id": "ex:1",
            "test": "foo"
          }
        }),
        output: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "https://example.com#",
            "ex": "http://example.org/",
            "claim": {
              "@id": "ex:claim",
              "@container": "@graph"
            },
            "id": "@id"
          },
          "claim": {
            "id": "ex:1",
            "test": "foo"
          }
        }),
        processingMode: 'json-ld-1.1'
      }
    }.each do |title, params|
      it title do
        do_frame(params)
      end
    end
  end

  context "problem cases" do
    {
      'pr #20': {
        frame: %({}),
        input: %([
          {
            "@id": "_:gregg",
            "@type": "http://xmlns.com/foaf/0.1/Person",
            "http://xmlns.com/foaf/0.1/name": "Gregg Kellogg"
          }, {
            "@id": "http://manu.sporny.org/#me",
            "@type": "http://xmlns.com/foaf/0.1/Person",
            "http://xmlns.com/foaf/0.1/knows": {"@id": "_:gregg"},
            "http://xmlns.com/foaf/0.1/name": "Manu Sporny"
          }
        ]),
        output: %({
          "@graph": [
            {
              "@id": "_:b0",
              "@type": "http://xmlns.com/foaf/0.1/Person",
              "http://xmlns.com/foaf/0.1/name": "Gregg Kellogg"
            },
            {
              "@id": "http://manu.sporny.org/#me",
              "@type": "http://xmlns.com/foaf/0.1/Person",
              "http://xmlns.com/foaf/0.1/knows": {
                "@id": "_:b0",
                "@type": "http://xmlns.com/foaf/0.1/Person",
                "http://xmlns.com/foaf/0.1/name": "Gregg Kellogg"
              },
              "http://xmlns.com/foaf/0.1/name": "Manu Sporny"
            }
          ]
        })
      },
      'issue #28': {
        frame: %({
          "@context": {
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "talksAbout": {
              "@id": "http://www.myresource.com/ontology/1.0#talksAbout",
              "@type": "@id"
            },
            "label": {
              "@id": "rdfs:label",
              "@language": "en"
            }
          },
          "@id": "http://www.myresource/uuid"
        }),
        input: %({
          "@context": {
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#"
          },
          "@id": "http://www.myresource/uuid",
          "http://www.myresource.com/ontology/1.0#talksAbout": [
            {
              "@id": "http://rdf.freebase.com/ns/m.018w8",
              "rdfs:label": [
                {
                  "@value": "Basketball",
                  "@language": "en"
                }
              ]
            }
          ]
        }),
        output: %({
          "@context": {
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "talksAbout": {
              "@id": "http://www.myresource.com/ontology/1.0#talksAbout",
              "@type": "@id"
            },
            "label": {
              "@id": "rdfs:label",
              "@language": "en"
            }
          },
          "@graph": [
            {
              "@id": "http://www.myresource/uuid",
              "talksAbout": {
                "@id": "http://rdf.freebase.com/ns/m.018w8",
                "label": "Basketball"
              }
            }
          ]
        })
      },
      'PR #663 - Multiple named graphs': {
        frame: %({
          "@context": {
            "@vocab": "http://example.com/",
            "loves": {"@type": "@id"},
            "unionOf": {
              "@type": "@id",
              "@id": "owl:unionOf",
              "@container": "@list"
            },
            "Class": "owl:Class"
          },
          "@graph": [
            {
              "@explicit": false,
              "@embed": "@once",
              "@type": ["Act", "Class"],
              "@graph": [{
                "@explicit": true,
                "@embed": "@always",
                "@type": "Person",
                "@id": {},
                "loves": {"@embed": "@never"}
              }]
            }
          ]
        }),
        input: %({
          "@context": {
            "@vocab": "http://example.com/",
            "loves": {"@type": "@id"},
            "unionOf": {
              "@type": "@id",
              "@id": "owl:unionOf",
              "@container": "@list"
            },
            "Class": "owl:Class"
          },
          "@graph": [{
            "@type": "Act",
            "@graph": [
              {"@id": "Romeo", "@type": "Person"},
              {"@id": "Juliet", "@type": "Person"}
            ]
          }, {
            "@id": "ActTwo",
            "@type": "Act",
            "@graph": [
              {"@id": "Romeo", "@type": "Person", "loves": "Juliet"},
              {"@id": "Juliet", "@type": "Person", "loves": "Romeo"}
            ]
          }, {
            "@id": "Person",
            "@type": "Class",
            "unionOf": {
              "@list": [
                {"@id": "Montague", "@type": "Class"},
                {"@id": "Capulet", "@type": "Class"}
              ]
            }
          }]
        }),
        output: %({
          "@context": {
            "@vocab": "http://example.com/",
            "loves": {"@type": "@id"},
            "unionOf": {
              "@type": "@id",
              "@id": "owl:unionOf",
              "@container": "@list"
            },
            "Class": "owl:Class"
          },
          "@graph": [{
            "@id": "ActTwo",
            "@type": "Act",
            "@graph": [
              {"@id": "Juliet", "@type": "Person", "loves": "Romeo"},
              {"@id": "Romeo", "@type": "Person", "loves": "Juliet"}
            ]
          }, {
            "@id": "Capulet",
            "@type": "Class"
          }, {
            "@id": "Montague",
            "@type": "Class"
          }, {
            "@id": "Person",
            "@type": "Class",
            "unionOf": [
              {"@id": "Montague", "@type": "Class"},
              {"@id": "Capulet", "@type": "Class"}
            ]
          }, {
            "@type": "Act",
            "@graph": [
              {
                "@id": "Juliet",
                "@type": "Person",
                "loves": null
              }, {
                "@id": "Romeo",
                "@type": "Person",
                "loves": null
              }
            ]
          }]
        }),
        processingMode: 'json-ld-1.1'
      },
      'w3c/json-ld-framing#5': {
        frame: %({
          "@context" : {
            "@vocab" : "http://purl.bdrc.io/ontology/core/",
            "taxSubclassOf" : {
              "@id" : "http://purl.bdrc.io/ontology/core/taxSubclassOf",
              "@type" : "@id"
            },
            "bdr" : "http://purl.bdrc.io/resource/",
            "children": { "@reverse": "http://purl.bdrc.io/ontology/core/taxSubclassOf" }
          },
          "@id" : "bdr:O9TAXTBRC201605",
          "children": {
            "children": {
              "children": {}
            }
          }
        }),
        input: %({
          "@context": {
            "@vocab": "http://purl.bdrc.io/ontology/core/",
            "taxSubclassOf": {
              "@id": "http://purl.bdrc.io/ontology/core/taxSubclassOf",
              "@type": "@id"
            },
            "bdr": "http://purl.bdrc.io/resource/"
          },
          "@graph": [{
            "@id": "bdr:O9TAXTBRC201605",
            "@type": "Taxonomy"
          }, {
            "@id": "bdr:O9TAXTBRC201605_0001",
            "@type": "Taxonomy",
            "taxSubclassOf": "bdr:O9TAXTBRC201605"
          }, {
            "@id": "bdr:O9TAXTBRC201605_0002",
            "@type": "Taxonomy",
            "taxSubclassOf": "bdr:O9TAXTBRC201605_0001"
          }, {
            "@id": "bdr:O9TAXTBRC201605_0010",
            "@type": "Taxonomy",
            "taxSubclassOf": "bdr:O9TAXTBRC201605"
          }]
        }),
        output: %({
          "@context" : {
            "@vocab" : "http://purl.bdrc.io/ontology/core/",
            "taxSubclassOf" : {
              "@id" : "http://purl.bdrc.io/ontology/core/taxSubclassOf",
              "@type" : "@id"
            },
            "bdr" : "http://purl.bdrc.io/resource/",
            "children": { "@reverse": "http://purl.bdrc.io/ontology/core/taxSubclassOf" }
          },
          "@id" : "bdr:O9TAXTBRC201605",
          "@type": "Taxonomy",
          "children": [{
            "@id": "bdr:O9TAXTBRC201605_0001",
            "@type": "Taxonomy",
            "taxSubclassOf": "bdr:O9TAXTBRC201605",
            "children": {
              "@id": "bdr:O9TAXTBRC201605_0002",
              "@type": "Taxonomy",
              "taxSubclassOf": "bdr:O9TAXTBRC201605_0001"
            }
          }, {
            "@id": "bdr:O9TAXTBRC201605_0010",
            "@type": "Taxonomy",
            "taxSubclassOf": "bdr:O9TAXTBRC201605"
          }]
        }),
        processingMode: 'json-ld-1.1'
      },
      'issue json-ld-framing#30': {
        input: %({
          "@context": {"eg": "https://example.org/ns/"},
          "@id": "https://example.org/what",
          "eg:sameAs": "https://example.org/what",
          "eg:age": 42
        }),
        frame: %({
          "@context": {"eg": "https://example.org/ns/"},
          "@id": "https://example.org/what"
        }),
        output: %({
          "@context": {"eg": "https://example.org/ns/"},
          "@graph": [{
            "@id": "https://example.org/what",
            "eg:age": 42,
            "eg:sameAs": "https://example.org/what"
          }]
        })
      },
      'issue json-ld-framing#64': {
        input: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "http://example.org/vocab#"
          },
          "@id": "http://example.org/1",
          "@type": "HumanMadeObject",
          "produced_by": {
            "@type": "Production",
            "_label": "Top Production",
            "part": {
              "@type": "Production",
              "_label": "Test Part"
            }
          }
        }),
        frame: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "http://example.org/vocab#",
            "Production": {
              "@context": {
                "part": {
                  "@type": "@id",
                  "@container": "@set"
                }
              }
            }
          },
          "@id": "http://example.org/1"
        }),
        output: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "http://example.org/vocab#",
            "Production": {
              "@context": {
                "part": {
                  "@type": "@id",
                  "@container": "@set"
                }
              }
            }
          },
          "@id": "http://example.org/1",
          "@type": "HumanMadeObject",
          "produced_by": {
            "@type": "Production",
            "part": [{
              "@type": "Production",
              "_label": "Test Part"
            }],
            "_label": "Top Production"
          }
        }),
        processingMode: "json-ld-1.1"
      },
      'issue json-ld-framing#27': {
        input: %({
          "@id": "ex:cred",
          "ex:subject": {
            "@id": "ex:Subject",
            "ex:name": "the subject",
            "ex:knows": {
              "@id": "ex:issuer",
              "ex:name": "Someone else"
            }
          },
          "ex:proof": {
            "@graph": {
              "@type": "ex:Proof",
              "ex:name": "the proof",
              "ex:signer": [{
                "@id": "ex:Subject",
                "ex:name": "something different"
              }]
            }
          }
        }),
        frame: %({
          "@context": {
            "@version": 1.1,
            "proof": {"@id": "ex:proof", "@container": "@graph"}
          },
          "@graph": {
            "subject": {},
            "proof": {}
          }
        }),
        output: %({
          "@context": {
            "@version": 1.1,
            "proof": {
              "@id": "ex:proof",
              "@container": "@graph"
            }
          },
          "@id": "ex:cred",
          "ex:subject": {
            "@id": "ex:Subject",
            "ex:name": "the subject",
            "ex:knows": {
              "@id": "ex:issuer",
              "ex:name": "Someone else"
            }
          },
          "proof": {
            "@type": "ex:Proof",
            "ex:name": "the proof",
            "ex:signer": {
              "@id": "ex:Subject",
              "ex:name": "something different"
            }
          }
        }),
        processingMode: "json-ld-1.1"
      },
      'missing types': {
        input: %({
            "@context": {
              "ex": "http://example.com#",
              "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
            },
            "@graph": [{
              "@id": "ex:graph1",
              "@graph": [{
                "@id": "ex:entity1",
                "@type": ["ex:Type1","ex:Type2"],
                "ex:title": "some title",
                "ex:multipleValues": "ex:One"
            }]
          }, {
            "@id": "ex:graph2",
            "@graph": [{
              "@id": "ex:entity1",
              "@type": "ex:Type3",
              "ex:tags": "tag1 tag2",
              "ex:multipleValues": ["ex:Two","ex:Three"]
            }]
          }]
        }),
        output: %({
          "@context": {
            "ex": "http://example.com#",
            "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
          },
          "@id": "ex:entity1",
          "@type": ["ex:Type1", "ex:Type2", "ex:Type3"],
          "ex:multipleValues": ["ex:One", "ex:Two","ex:Three"],
          "ex:tags": "tag1 tag2",
          "ex:title": "some title"
        }),
        frame: %({
          "@context": {
            "ex": "http://example.com#",
            "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
          },
          "@id": "ex:entity1"
        }),
        processingMode: "json-ld-1.1"
      },
      "don't embed list elements": {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:embed": {
            "@list": [{"@embed": "@never"}]
          }
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:embed": {
            "@list": [{
              "@id": "ex:Sub2",
              "ex:prop": "property"
            }]
          }
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:embed": {"@list": [{"@id": "ex:Sub2"}]}
        }),
        processingMode: "json-ld-1.1"
      },
      'issue #142': {
        input: %({
          "@context":{
            "ex":"http://example.org/vocab#",
            "ex:info":{"@type":"@json"},
            "ex:other":{"@type":"@json"}
          },
          "@id":"http://example.org/test/#library",
          "@type":"ex:Library",
          "ex:info":{
            "author":"JOHN",
            "pages":200
          },
          "ex:other":{
            "publisher":"JANE"
          }
        }),
        frame: %({
          "@context":{
            "ex":"http://example.org/vocab#",
            "ex:info":{"@type":"@json"},
            "ex:other":{"@type":"@json"}
          },
          "http://example.org/vocab#info":{}
        }),
        output: %({
          "@context": {
            "ex": "http://example.org/vocab#",
            "ex:info": {"@type": "@json"},
            "ex:other": {"@type": "@json"}
          },
          "@id": "http://example.org/test/#library",
          "@type": "ex:Library",
          "ex:info": {
            "author": "JOHN",
            "pages": 200
          },
          "ex:other": {
            "publisher": "JANE"
          }
        }),
        processingMode: "json-ld-1.1"
      },
      "ruby-rdf/json-ld#62": {
        input: %({
          "@context": {
            "@vocab": "http://schema.org/"
          },
          "@type": "Event",
          "location": {
            "@id": "http://kg.artsdata.ca/resource/K11-200"
          }
        }),
        frame: %({
          "@context": {
            "@vocab": "http://schema.org/",
            "location": {
              "@type": "@id",
              "@container": "@type"
            }
          },
          "@type": "Event"
        }),
        output: %({
          "@context": {
            "@vocab": "http://schema.org/",
            "location": {
              "@type": "@id",
              "@container": "@type"
            }
          },
          "@type": "Event",
          "location": {
            "@none": "http://kg.artsdata.ca/resource/K11-200"
          }
        }),
        processingMode: "json-ld-1.1"
      }
    }.each do |title, params|
      it title do
        do_frame(params)
      end
    end
  end

  def do_frame(params)
    input = params[:input]
    frame = params[:frame]
    output = params[:output]
    params = { processingMode: 'json-ld-1.0' }.merge(params)
    input = JSON.parse(input) if input.is_a?(String)
    frame = JSON.parse(frame) if frame.is_a?(String)
    output = JSON.parse(output) if output.is_a?(String)
    jld = nil
    if params[:write]
      expect { jld = JSON::LD::API.frame(input, frame, logger: logger, **params) }.to write(params[:write]).to(:error)
    else
      expect { jld = JSON::LD::API.frame(input, frame, logger: logger, **params) }.not_to write.to(:error)
    end
    expect(jld).to produce_jsonld(output, logger)

    # Compare expanded jld/output too to make sure list values remain ordered
    exp_jld = JSON::LD::API.expand(jld, processingMode: 'json-ld-1.1')
    exp_output = JSON::LD::API.expand(output, processingMode: 'json-ld-1.1')
    expect(exp_jld).to produce_jsonld(exp_output, logger)
  rescue JSON::LD::JsonLdError => e
    raise("#{e.class}: #{e.message}\n" \
          "#{logger}\n" \
          "Backtrace:\n#{e.backtrace.join("\n")}")
  end
end
