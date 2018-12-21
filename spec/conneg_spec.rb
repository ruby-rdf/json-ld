# coding: utf-8
require_relative 'spec_helper'
require 'rack/linkeddata'
require 'rack/test'

describe JSON::LD::ContentNegotiation do
  include ::Rack::Test::Methods
  let(:logger) {RDF::Spec.logger}

  let(:app) do
    described_class.new(double("Target Rack Application", :call => [200, {}, @results || "A String"]))
  end

  describe "#parse_accept_header" do
    {
      "application/n-triples, application/ld+json;q=0.5" => %w(application/ld+json),
      "application/ld+json, application/ld+json;profile=http://www.w3.org/ns/json-ld#compacted" =>
        %w(application/ld+json;profile=http://www.w3.org/ns/json-ld#compacted application/ld+json),
    }.each do |accept, content_types|
      it "returns #{content_types.inspect} given #{accept.inspect}" do
        expect(app.send(:parse_accept_header, accept)).to eq content_types
      end
    end
  end

  describe "#find_content_type_for_media_range" do
    {
      "*/*" => "application/ld+json",
      "application/*" => "application/ld+json",
      "application/json" => "application/ld+json",
      "application/json;profile=http://www.w3.org/ns/json-ld#compacted" =>
        "application/ld+json;profile=http://www.w3.org/ns/json-ld#compacted",
      "text/plain" => nil
    }.each do |media_range, content_type|
      it "returns #{content_type.inspect} for #{media_range.inspect}" do
        expect(app.send(:find_content_type_for_media_range, media_range)).to eq content_type
      end
    end
  end

  describe "#call" do
    let(:schema_context) {
      RDF::Util::File::RemoteDocument.new(%q({
        "@context": {
          "@vocab": "http://schema.org/",
          "id": "@id",
          "type": "@type"
        }
      }), base_uri: "http://schema.org")
    }
    let(:frame) {
      RDF::Util::File::RemoteDocument.new(%q({
        "@context": {
          "dc": "http://purl.org/dc/elements/1.1/",
          "ex": "http://example.org/vocab#"
        },
        "@type": "ex:Library",
        "ex:contains": {
          "@type": "ex:Book",
          "ex:contains": {
            "@type": "ex:Chapter"
          }
        }
      }), base_uri: "http://conneg.example.com/frame")
    }
    let(:context) {
      RDF::Util::File::RemoteDocument.new(%q({
        "@context": {
          "dc": "http://purl.org/dc/elements/1.1/",
          "ex": "http://example.org/vocab#"
        }
      }), base_uri: "http://conneg.example.com/context")
    }

    before(:each) do
      allow(JSON::LD::API).to receive(:documentLoader).with("http://schema.org", any_args).and_yield(schema_context)
      allow(JSON::LD::API).to receive(:documentLoader).with("http://conneg.example.com/context", any_args).and_yield(context)
      allow(JSON::LD::API).to receive(:documentLoader).with("http://conneg.example.com/frame", any_args).and_return(frame)
    end

    context "with text result" do
      it "returns text unchanged" do
        get '/'
        expect(last_response.body).to eq 'A String'
      end
    end

    context "with object result" do
      before(:each) do
        @results = LIBRARY_INPUT
      end

      it "returns expanded result" do
        get '/'
        expect(JSON.parse(last_response.body)).to produce_jsonld(LIBRARY_EXPANDED, logger)
      end

      context "with Accept" do
        {
          "application/n-triples"                           => "406 Not Acceptable (No appropriate combinaion of media-type and parameters found)\n",
          "application/json"                                => LIBRARY_EXPANDED,
          "application/ld+json"                             => LIBRARY_EXPANDED,
          %(application/ld+json;profile=http://www.w3.org/ns/json-ld#expanded) =>
                                                               LIBRARY_EXPANDED,

          %(application/ld+json;profile=http://www.w3.org/ns/json-ld#compacted) =>
                                                               LIBRARY_COMPACTED_DEFAULT,
          %(application/ld+json;profile=http://conneg.example.com/context) =>
                                                               LIBRARY_COMPACTED,
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://conneg.example.com/context") =>
                                                               LIBRARY_COMPACTED,
          %(application/ld+json;profile="http://conneg.example.com/context http://www.w3.org/ns/json-ld#compacted") =>
                                                               LIBRARY_COMPACTED,

          %(application/ld+json;profile=http://www.w3.org/ns/json-ld#flattened) =>
                                                               LIBRARY_FLATTENED_EXPANDED,
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#flattened http://www.w3.org/ns/json-ld#expanded") =>
                                                               LIBRARY_FLATTENED_EXPANDED,
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#expanded http://www.w3.org/ns/json-ld#flattened") =>
                                                               LIBRARY_FLATTENED_EXPANDED,

          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#flattened http://www.w3.org/ns/json-ld#compacted") =>
                                                               LIBRARY_FLATTENED_COMPACTED_DEFAULT,
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://www.w3.org/ns/json-ld#flattened") =>
                                                               LIBRARY_FLATTENED_COMPACTED_DEFAULT,

          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#flattened http://conneg.example.com/context") =>
                                                               LIBRARY_FLATTENED_COMPACTED,
          %(application/ld+json;profile="http://conneg.example.com/context http://www.w3.org/ns/json-ld#flattened") =>
                                                               LIBRARY_FLATTENED_COMPACTED,

          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#framed http://conneg.example.com/frame") =>
                                                               LIBRARY_FRAMED,
          %(application/ld+json;profile="http://conneg.example.com/frame http://www.w3.org/ns/json-ld#framed") =>
                                                               LIBRARY_FRAMED,

          %(application/ld+json;profile=http://www.w3.org/ns/json-ld#framed) =>
                                                               "406 Not Acceptable (No appropriate combinaion of media-type and parameters found)\n",
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#framed http://www.w3.org/ns/json-ld#expanded") =>
                                                               "406 Not Acceptable (No appropriate combinaion of media-type and parameters found)\n",
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#expanded http://www.w3.org/ns/json-ld#framed") =>
                                                               "406 Not Acceptable (No appropriate combinaion of media-type and parameters found)\n",
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#framed http://www.w3.org/ns/json-ld#compacted") =>
                                                               "406 Not Acceptable (No appropriate combinaion of media-type and parameters found)\n",
          %(application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://www.w3.org/ns/json-ld#framed") =>
                                                               "406 Not Acceptable (No appropriate combinaion of media-type and parameters found)\n",
        }.each do |accepts, result|
          context accepts do
            before(:each) do
              get '/', {}, {"HTTP_ACCEPT" => accepts}
            end

            it "status" do
              expect(last_response.status).to satisfy("200 or 406") {|x| [200, 406].include?(x)}
            end

            it "sets content type" do
              expect(last_response.content_type).to eq(last_response.status == 406 ? 'text/plain' : 'application/ld+json')
            end

            it "returns serialization" do
              if last_response.status == 406
                expect(last_response.body).to eq result
              else
                expect(JSON.parse(last_response.body)).to produce_jsonld(result, logger)
              end
            end
          end
        end
      end
    end
  end
end

describe Rack::LinkedData::ContentNegotiation do
  include ::Rack::Test::Methods
  let(:logger) {RDF::Spec.logger}

  let(:app) do
    graph = RDF::NTriples::Reader.new(%(
      <http://example.org/library> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#Library> .
      <http://example.org/library> <http://example.org/vocab#contains> <http://example.org/library/the-republic> .
      <http://example.org/library/the-republic> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#Book> .
      <http://example.org/library/the-republic> <http://purl.org/dc/elements/1.1/title> "The Republic" .
      <http://example.org/library/the-republic> <http://purl.org/dc/elements/1.1/creator> "Plato" .
      <http://example.org/library/the-republic> <http://example.org/vocab#contains> <http://example.org/library/the-republic#introduction> .
      <http://example.org/library/the-republic#introduction> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#Chapter> .
      <http://example.org/library/the-republic#introduction> <http://purl.org/dc/elements/1.1/title> "The Introduction" .
      <http://example.org/library/the-republic#introduction> <http://purl.org/dc/elements/1.1/description> "An introductory chapter on The Republic." .
    ))
    Rack::LinkedData::ContentNegotiation.new(double("Target Rack Application", :call => [200, {}, graph]), {})
  end

  describe "#call" do
    let(:schema_context) {
      RDF::Util::File::RemoteDocument.new(%q({
        "@context": {
          "@vocab": "http://schema.org/",
          "id": "@id",
          "type": "@type"
        }
      }), base_uri: "http://schema.org")
    }
    let(:frame) {
      RDF::Util::File::RemoteDocument.new(%q({
        "@context": {
          "dc": "http://purl.org/dc/elements/1.1/",
          "ex": "http://example.org/vocab#"
        },
        "@type": "ex:Library",
        "ex:contains": {
          "@type": "ex:Book",
          "ex:contains": {
            "@type": "ex:Chapter"
          }
        }
      }), base_uri: "http://conneg.example.com/frame")
    }
    let(:context) {
      RDF::Util::File::RemoteDocument.new(%q({
        "@context": {
          "dc": "http://purl.org/dc/elements/1.1/",
          "ex": "http://example.org/vocab#"
        }
      }), base_uri: "http://conneg.example.com/context")
    }

    before(:each) do
      allow(JSON::LD::API).to receive(:documentLoader).with("http://schema.org", any_args).and_yield(schema_context)
      allow(JSON::LD::API).to receive(:documentLoader).with("http://conneg.example.com/context", any_args).and_yield(context)
      allow(JSON::LD::API).to receive(:documentLoader).with("http://conneg.example.com/frame", any_args).and_return(frame)
    end

    {
      "application/json"                                => LIBRARY_FLATTENED_EXPANDED,
      "application/ld+json"                             => LIBRARY_FLATTENED_EXPANDED,
      %(application/ld+json;profile=http://www.w3.org/ns/json-ld#expanded) =>
                                                           LIBRARY_FLATTENED_EXPANDED,

      %(application/ld+json;profile=http://www.w3.org/ns/json-ld#compacted) =>
                                                           LIBRARY_FLATTENED_COMPACTED_DEFAULT,
      %(application/ld+json;profile=http://conneg.example.com/context) =>
                                                           LIBRARY_FLATTENED_COMPACTED,
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://conneg.example.com/context") =>
                                                           LIBRARY_FLATTENED_COMPACTED,
      %(application/ld+json;profile="http://conneg.example.com/context http://www.w3.org/ns/json-ld#compacted") =>
                                                           LIBRARY_FLATTENED_COMPACTED,

      %(application/ld+json;profile=http://www.w3.org/ns/json-ld#flattened) =>
                                                           LIBRARY_FLATTENED_EXPANDED,
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#flattened http://www.w3.org/ns/json-ld#expanded") =>
                                                           LIBRARY_FLATTENED_EXPANDED,
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#expanded http://www.w3.org/ns/json-ld#flattened") =>
                                                           LIBRARY_FLATTENED_EXPANDED,

      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#flattened http://www.w3.org/ns/json-ld#compacted") =>
                                                           LIBRARY_FLATTENED_COMPACTED_DEFAULT,
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://www.w3.org/ns/json-ld#flattened") =>
                                                           LIBRARY_FLATTENED_COMPACTED_DEFAULT,

      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#flattened http://conneg.example.com/context") =>
                                                           LIBRARY_FLATTENED_COMPACTED,
      %(application/ld+json;profile="http://conneg.example.com/context http://www.w3.org/ns/json-ld#flattened") =>
                                                           LIBRARY_FLATTENED_COMPACTED,

      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#framed http://conneg.example.com/frame") =>
                                                           LIBRARY_FRAMED,
      %(application/ld+json;profile="http://conneg.example.com/frame http://www.w3.org/ns/json-ld#framed") =>
                                                           LIBRARY_FRAMED,

      %(application/ld+json;profile=http://www.w3.org/ns/json-ld#framed) =>
                                                           "406 Not Acceptable\n",
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#framed http://www.w3.org/ns/json-ld#expanded") =>
                                                           "406 Not Acceptable\n",
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#expanded http://www.w3.org/ns/json-ld#framed") =>
                                                           "406 Not Acceptable\n",
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#framed http://www.w3.org/ns/json-ld#compacted") =>
                                                           "406 Not Acceptable\n",
      %(application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://www.w3.org/ns/json-ld#framed") =>
                                                           "406 Not Acceptable\n",
    }.each do |accepts, result|
      context accepts do
        before(:each) do
          get '/', {}, {"HTTP_ACCEPT" => accepts}
        end

        it "status" do
          expect(last_response.status).to satisfy("200 or 406") {|x| [200, 406].include?(x)}
        end

        it "sets content type" do
          expect(last_response.content_type).to eq(last_response.status == 406 ? 'text/plain' : 'application/ld+json')
        end

        it "returns serialization" do
          if last_response.status == 406
            expect(last_response.body).to eq result
          else
            expect(JSON.parse(last_response.body)).to produce_jsonld(result, logger)
          end
        end
      end
    end
  end
end
