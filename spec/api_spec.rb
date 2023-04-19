# frozen_string_literal: true

require_relative 'spec_helper'

describe JSON::LD::API do
  let(:logger) { RDF::Spec.logger }

  before { JSON::LD::Context::PRELOADED.clear }

  describe "#initialize" do
    context "with string input" do
      let(:context) do
        JSON::LD::API::RemoteDocument.new('{
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "name": "http://xmlns.com/foaf/0.1/name",
            "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
            "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
          }
          }',
          documentUrl: "http://example.com/context",
          contentType: 'application/ld+json')
      end
      let(:remote_doc) do
        JSON::LD::API::RemoteDocument.new('{"@id": "", "name": "foo"}',
          documentUrl: "http://example.com/foo",
          contentType: 'application/ld+json',
          contextUrl: "http://example.com/context")
      end

      it "loads document with loader and loads context" do
        expect(described_class).to receive(:documentLoader).with("http://example.com/foo",
          anything).and_yield(remote_doc)
        expect(described_class).to receive(:documentLoader).with("http://example.com/context",
          anything).and_yield(context)
        described_class.new("http://example.com/foo", nil)
      end
    end
  end

  context "when validating", pending: ("JRuby support for jsonlint" if RUBY_ENGINE == "jruby") do
    it "detects invalid JSON" do
      expect do
        described_class.new(StringIO.new(%({"a": "b", "a": "c"})), nil,
          validate: true)
      end.to raise_error(JSON::LD::JsonLdError::LoadingDocumentFailed)
    end
  end

  context "Test Files" do
    %i[oj json_gem ok_json yajl].each do |adapter|
      context "with MultiJson adapter #{adapter.inspect}" do
        Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'test-files/*-input.*'))) do |filename|
          test = File.basename(filename).sub(/-input\..*$/, '')
          frame = filename.sub(/-input\..*$/, '-frame.jsonld')
          framed = filename.sub(/-input\..*$/, '-framed.jsonld')
          compacted = filename.sub(/-input\..*$/, '-compacted.jsonld')
          context = filename.sub(/-input\..*$/, '-context.jsonld')
          expanded = filename.sub(/-input\..*$/, '-expanded.jsonld')
          ttl = filename.sub(/-input\..*$/, '-rdf.ttl')

          context test,
            skip: ("Not supported in JRuby" if RUBY_ENGINE == "jruby" && %w[oj yajl].include?(adapter.to_s)) do
            around do |example|
              @file = File.open(filename)
              case filename
              when /.jsonld$/
                @file.define_singleton_method(:content_type) { 'application/ld+json' }
              end
              if context
                @ctx_io = File.open(context)
                case context
                when /.jsonld$/
                  @ctx_io.define_singleton_method(:content_type) { 'application/ld+json' }
                end
              end
              example.run
              @file.close
              @ctx_io&.close
            end

            if File.exist?(expanded)
              it "expands" do
                options = { logger: logger, adapter: adapter }
                options[:expandContext] = @ctx_io if context
                jld = described_class.expand(@file, **options)
                expect(jld).to produce_jsonld(JSON.parse(File.read(expanded)), logger)
              end

              it "expands with serializer" do
                options = { logger: logger, adapter: adapter }
                options[:expandContext] = @ctx_io if context
                jld = described_class.expand(@file, serializer: described_class.method(:serializer), **options)
                expect(jld).to be_a(String)
                expect(JSON.parse(jld)).to produce_jsonld(JSON.parse(File.read(expanded)), logger)
              end
            end

            if File.exist?(compacted) && File.exist?(context)
              it "compacts" do
                jld = described_class.compact(@file, @ctx_io, adapter: adapter, logger: logger)
                expect(jld).to produce_jsonld(JSON.parse(File.read(compacted)), logger)
              end

              it "compacts with serializer" do
                jld = described_class.compact(@file, @ctx_io, serializer: described_class.method(:serializer),
                  adapter: adapter, logger: logger)
                expect(jld).to be_a(String)
                expect(JSON.parse(jld)).to produce_jsonld(JSON.parse(File.read(compacted)), logger)
              end
            end

            if File.exist?(framed) && File.exist?(frame)
              it "frames" do
                File.open(frame) do |frame_io|
                  jld = described_class.frame(@file, frame_io, adapter: adapter, logger: logger)
                  expect(jld).to produce_jsonld(JSON.parse(File.read(framed)), logger)
                end
              end

              it "frames with serializer" do
                File.open(frame) do |frame_io|
                  jld = described_class.frame(@file, frame_io, serializer: described_class.method(:serializer),
                    adapter: adapter, logger: logger)
                  expect(jld).to be_a(String)
                  expect(JSON.parse(jld)).to produce_jsonld(JSON.parse(File.read(framed)), logger)
                end
              end
            end

            if File.exist?(ttl)
              it "toRdf" do
                expect(RDF::Repository.load(filename, format: :jsonld, adapter: adapter,
                  logger: logger)).to be_equivalent_graph(RDF::Repository.load(ttl), logger: logger)
              end
            end
          end
        end
      end
    end
  end
end
