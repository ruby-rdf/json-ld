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
            "@id" => "_:t0",
            "@type" => [RDF::FOAF.Person.to_s]
          },
          {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "_:t0"}]
          },
          {"@id" => RDF::FOAF.Person.to_s},
          {"@id" => RDF::FOAF.PersonalProfile.to_s},
        ]
      }
    }.each do |title, params|
      it title do
        @debug = []
        jld = JSON::LD::API.flatten(params[:input], nil, nil, :debug => @debug) 
        jld.should produce(params[:output], @debug)
      end
    end
  end
end
