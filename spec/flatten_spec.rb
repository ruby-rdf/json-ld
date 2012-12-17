# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe "#generate_node_map" do
    {
      "single object" => {
        :input => {"@id" => "http://example.com", "@type" => RDF::RDFS.Resource.to_s},
        :subjects => %w(http://example.com),
        :output => {
          "http://example.com" => {
            "@id" => "http://example.com", "@type" => [RDF::RDFS.Resource.to_s]
          }
        }
      },
      "embedded object" => {
        :input => {
          "@context" => {"foaf" => RDF::FOAF.to_s},
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => ["foaf:PersonalProfile"],
          "foaf:primaryTopic" => [{
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => ["foaf:Person"]
          }]
        },
        :subjects => %w(http://greggkellogg.net/foaf http://greggkellogg.net/foaf#me),
        :output => {
          "http://greggkellogg.net/foaf" => {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "http://greggkellogg.net/foaf#me"}]
          },
          "http://greggkellogg.net/foaf#me" => {
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => [RDF::FOAF.Person.to_s]
          }
        }
      },
      "embedded anon" => {
        :input => {
          "@context" => {"foaf" => RDF::FOAF.to_s},
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => "foaf:PersonalProfile",
          "foaf:primaryTopic" => {
            "@type" => "foaf:Person"
          }
        },
        :subjects => %w(http://greggkellogg.net/foaf _:t0),
        :output => {
          "_:t0" => {
            "@id" => "_:t0",
            "@type" => [RDF::FOAF.Person.to_s]
          },
          "http://greggkellogg.net/foaf" => {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "_:t0"}]
          },
        }
      },
      "anon in list" => {
        :input => [{
          "@id" => "_:a",
          "http://example.com/list" => [{"@list" => [{"@id" => "_:b"}]}]
        }, {
          "@id" => "_:b",
          "http://example.com/name" => "foo"
        }],
        :subjects => %w(_:t0 _:t1),
        :output => {
          "_:t0" => {
            "@id" => "_:t0",
            "http://example.com/list" => [
              {
                "@list" => [
                  {
                    "@id" => "_:t1"
                  }
                ]
              }
            ]
          },
          "_:t1" => {
            "@id" => "_:t1",
            "http://example.com/name" => [
              {
                "@value" => "foo"
              }
            ]
          }
        }
      }
    }.each do |title, params|
      it title do
        @debug = []
        @node_map = Hash.ordered
        graph = params[:graph] || '@merged'
        jld = nil
        JSON::LD::API.new(params[:input], nil, :debug => @debug) do |api|
          expanded_value = api.expand(api.value, nil, JSON::LD::BlankNodeNamer.new("e"), api.context)
          api.generate_node_map(expanded_value,
            @node_map,
            graph,
            nil,
            JSON::LD::BlankNodeNamer.new("t"))
        end
        @node_map.keys.should produce([graph], @debug)
        subjects = @node_map[graph]
        subjects.keys.should produce(params[:subjects], @debug)
        subjects.should produce(params[:output], @debug)
      end
    end
  end

  describe ".flatten" do
    {
      "single object" => {
        :input => {"@id" => "http://example.com", "@type" => RDF::RDFS.Resource.to_s},
        :output => [{"@id" => "http://example.com", "@type" => [RDF::RDFS.Resource.to_s]}]
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
          }
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
            "@id" => "_:t0",
            "@type" => [RDF::FOAF.Person.to_s]
          },
          {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "_:t0"}]
          },
        ]
      }
    }.each do |title, params|
      it title do
        @debug = []
        graph = params[:graph] || '@merged'
        jld = JSON::LD::API.flatten(params[:input], graph, nil, nil, :debug => @debug) 
        jld.should produce(params[:output], @debug)
      end
    end
  end
end
