# frozen_string_literal: true

require_relative 'spec_helper'
require 'rdf/spec/format'

describe JSON::LD::Format do
  it_behaves_like 'an RDF::Format' do
    let(:format_class) { described_class }
  end

  describe ".for" do
    formats = [
      :jsonld,
      "etc/doap.jsonld",
      { file_name:      'etc/doap.jsonld' },
      { file_extension: 'jsonld' },
      { content_type:   'application/ld+json' },
      { content_type:   'application/x-ld+json' }
    ].each do |arg|
      it "discovers with #{arg.inspect}" do
        expect(RDF::Format.for(arg)).to eq described_class
      end
    end

    {
      jsonld: '{"@context" => "foo"}',
      context: %({\n"@context": {),
      id: %({\n"@id": {),
      type: %({\n"@type": {)
    }.each do |sym, str|
      it "detects #{sym}" do
        expect(described_class.for { str }).to eq described_class
      end
    end

    it "discovers 'jsonld'" do
      expect(RDF::Format.for(:jsonld).reader).to eq JSON::LD::Reader
    end
  end

  describe "#to_sym" do
    specify { expect(described_class.to_sym).to eq :jsonld }
  end

  describe "#to_uri" do
    specify { expect(described_class.to_uri).to eq RDF::URI('http://www.w3.org/ns/formats/JSON-LD') }
  end

  describe ".detect" do
    {
      jsonld: '{"@context" => "foo"}'
    }.each do |sym, str|
      it "detects #{sym}" do
        expect(described_class.detect(str)).to be_truthy
      end
    end

    {
      n3: "@prefix foo: <bar> .\nfoo:bar = {<a> <b> <c>} .",
      nquads: "<a> <b> <c> <d> . ",
      rdfxml: '<rdf:RDF about="foo"></rdf:RDF>',
      rdfa: '<div about="foo"></div>',
      microdata: '<div itemref="bar"></div>',
      ntriples: "<a> <b> <c> .",
      multi_line: '<a>\n  <b>\n  "literal"\n .',
      turtle: "@prefix foo: <bar> .\n foo:a foo:b <c> ."
    }.each do |sym, str|
      it "does not detect #{sym}" do
        expect(described_class.detect(str)).to be_falsey
      end
    end
  end

  describe ".cli_commands", skip: Gem.win_platform? do
    require 'rdf/cli'
    let(:ttl) { File.expand_path('test-files/test-1-rdf.ttl', __dir__) }
    let(:json) { File.expand_path('test-files/test-1-input.jsonld', __dir__) }
    let(:context) { File.expand_path('test-files/test-1-context.jsonld', __dir__) }

    describe "#expand" do
      it "expands RDF" do
        expect { RDF::CLI.exec(["expand", ttl], format: :ttl, output_format: :jsonld) }.to write.to(:output)
      end

      it "expands JSON" do
        expect do
          RDF::CLI.exec(["expand", json], format: :jsonld, output_format: :jsonld, validate: false)
        end.to write.to(:output)
      end
    end

    describe "#compact" do
      it "compacts RDF" do
        expect do
          RDF::CLI.exec(["compact", ttl], context: context, format: :ttl, output_format: :jsonld,
            validate: false)
        end.to write.to(:output)
      end

      it "compacts JSON" do
        expect do
          RDF::CLI.exec(["compact", json], context: context, format: :jsonld, output_format: :jsonld,
            validate: false)
        end.to write.to(:output)
      end
    end

    describe "#flatten" do
      it "flattens RDF" do
        expect do
          RDF::CLI.exec(["flatten", ttl], context: context, format: :ttl, output_format: :jsonld,
            validate: false)
        end.to write.to(:output)
      end

      it "flattens JSON" do
        expect do
          RDF::CLI.exec(["flatten", json], context: context, format: :jsonld, output_format: :jsonld,
            validate: false)
        end.to write.to(:output)
      end
    end

    describe "#frame" do
      it "frames RDF" do
        expect do
          RDF::CLI.exec(["frame", ttl], frame: context, format: :ttl, output_format: :jsonld)
        end.to write.to(:output)
      end

      it "frames JSON" do
        expect do
          RDF::CLI.exec(["frame", json], frame: context, format: :jsonld, output_format: :jsonld,
            validate: false)
        end.to write.to(:output)
      end
    end
  end
end
