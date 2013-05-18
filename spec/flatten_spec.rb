# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".flatten" do
    {
      "single object" => {
        :input => {"@id" => "http://example.com", "@type" => RDF::RDFS.Resource.to_s},
        :output => [
          {"@id" => "http://example.com", "@type" => [RDF::RDFS.Resource.to_s]},
          {"@id" => RDF::RDFS.Resource.to_s}
        ]
      },
      "embedded object" => {
        :input => {
          "@context" => {
            "foaf" => RDF::FOAF.to_s
          },
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => ["foaf:PersonalProfile"],
          "foaf:primaryTopic" => [{
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => ["foaf:Person"]
          }]
        },
        :output => [
          {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "http://greggkellogg.net/foaf#me"}]
          },
          {
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => [RDF::FOAF.Person.to_s]
          },
          {"@id" => RDF::FOAF.Person.to_s},
          {"@id" => RDF::FOAF.PersonalProfile.to_s},
        ]
      },
      "embedded anon" => {
        :input => {
          "@context" => {
            "foaf" => RDF::FOAF.to_s
          },
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => "foaf:PersonalProfile",
          "foaf:primaryTopic" => {
            "@type" => "foaf:Person"
          }
        },
        :output => [
          {
            "@id" => "_:b0",
            "@type" => [RDF::FOAF.Person.to_s]
          },
          {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "_:b0"}]
          },
          {"@id" => RDF::FOAF.Person.to_s},
          {"@id" => RDF::FOAF.PersonalProfile.to_s},
        ]
      },
      "reverse properties" => {
        :input => ::JSON.parse(%([
          {
            "@id": "http://example.com/people/markus",
            "@reverse": {
              "http://xmlns.com/foaf/0.1/knows": [
                {
                  "@id": "http://example.com/people/dave"
                },
                {
                  "@id": "http://example.com/people/gregg"
                }
              ]
            },
            "http://xmlns.com/foaf/0.1/name": [ { "@value": "Markus Lanthaler" } ]
          }
        ])),
        :output => ::JSON.parse(%([
          {
            "@id": "http://example.com/people/dave",
            "http://xmlns.com/foaf/0.1/knows": [
              {
                "@id": "http://example.com/people/markus"
              }
            ]
          },
          {
            "@id": "http://example.com/people/gregg",
            "http://xmlns.com/foaf/0.1/knows": [
              {
                "@id": "http://example.com/people/markus"
              }
            ]
          },
          {
            "@id": "http://example.com/people/markus",
            "http://xmlns.com/foaf/0.1/name": [
              {
                "@value": "Markus Lanthaler"
              }
            ]
          }
        ]))
      },
      "Simple named graph (Wikidata)" => {
        :input => ::JSON.parse(%q({
          "@context": {
            "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
            "ex": "http://example.org/",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "ex:locatedIn": {"@type": "@id"},
            "ex:hasPopulaton": {"@type": "xsd:integer"},
            "ex:hasReference": {"@type": "@id"}
          },
          "@graph": [
            {
              "@id": "http://example.org/ParisFact1",
              "@type": "rdf:Graph",
              "@graph": {
                "@id": "http://example.org/location/Paris#this",
                "ex:locatedIn": "http://example.org/location/France#this"
              },
              "ex:hasReference": ["http://www.britannica.com/", "http://www.wikipedia.org/", "http://www.brockhaus.de/"]
            },
            {
              "@id": "http://example.org/ParisFact2",
              "@type": "rdf:Graph",
              "@graph": {
                "@id": "http://example.org/location/Paris#this",
                "ex:hasPopulation": 7000000
              },
              "ex:hasReference": "http://www.wikipedia.org/"
            }
          ]
        })),
        :output => ::JSON.parse(%q([{
          "@id": "http://example.org/ParisFact1",
          "@type": ["http://www.w3.org/1999/02/22-rdf-syntax-ns#Graph"],
          "http://example.org/hasReference": [
            {"@id": "http://www.britannica.com/"},
            {"@id": "http://www.wikipedia.org/"},
            {"@id": "http://www.brockhaus.de/"}
          ],
          "@graph": [{
              "@id": "http://example.org/location/France#this"
          }, {
              "@id": "http://example.org/location/Paris#this",
              "http://example.org/locatedIn": [{"@id": "http://example.org/location/France#this"}]
            }]
          }, {
            "@id": "http://example.org/ParisFact2",
            "@type": ["http://www.w3.org/1999/02/22-rdf-syntax-ns#Graph"],
            "http://example.org/hasReference": [{"@id": "http://www.wikipedia.org/"}],
            "@graph": [{
              "@id": "http://example.org/location/Paris#this",
              "http://example.org/hasPopulation": [{"@value": 7000000}]
            }]
          }, {
            "@id": "http://www.britannica.com/"
          }, {
            "@id": "http://www.brockhaus.de/"
          }, {
            "@id": "http://www.w3.org/1999/02/22-rdf-syntax-ns#Graph"
          }, {
            "@id": "http://www.wikipedia.org/"
          }])),
      },
      "Test Manifest (shortened)" => {
        :input => ::JSON.parse(%q{
          {
            "@id": "",
            "http://example/sequence": {"@list": [
              {
                "@id": "#t0001",
                "http://example/name": "Keywords cannot be aliased to other keywords",
                "http://example/input": {"@id": "error-expand-0001-in.jsonld"}
              }
            ]}
          }
        }),
        :output => ::JSON.parse(%q{
          [{
            "@id": "",
            "http://example/sequence": [{"@list": [{"@id": "#t0001"}]}]
          }, {
            "@id": "#t0001",
            "http://example/input": [{"@id": "error-expand-0001-in.jsonld"}],
            "http://example/name": [{"@value": "Keywords cannot be aliased to other keywords"}]
          }, {
            "@id": "error-expand-0001-in.jsonld"
          }]
        }),
        :options => {}
      }
    }.each do |title, params|
      it title do
        @debug = []
        jld = JSON::LD::API.flatten(params[:input], nil, (params[:options] || {}).merge(:debug => @debug)) 
        jld.should produce(params[:output], @debug)
      end
    end
  end
end
