# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/reader'

describe JSON::LD::Reader do
  let!(:doap) {File.expand_path("../../etc/doap.jsonld", __FILE__)}
  let!(:doap_nt) {File.expand_path("../../etc/doap.nt", __FILE__)}
  let!(:doap_count) {File.open(doap_nt).each_line.to_a.length}

  it_behaves_like 'an RDF::Reader' do
    let(:reader_input) {File.read(doap)}
    let(:reader) {JSON::LD::Reader.new(reader_input)}
    let(:reader_count) {doap_count}
  end

  describe ".for" do
    formats = [
      :jsonld,
      "etc/doap.jsonld",
      {file_name:      'etc/doap.jsonld'},
      {file_extension: 'jsonld'},
      {content_type:   'application/ld+json'},
      {content_type:   'application/x-ld+json'},
    ].each do |arg|
      it "discovers with #{arg.inspect}" do
        expect(RDF::Reader.for(arg)).to eq JSON::LD::Reader
      end
    end
  end

  context "when validating", pending: ("JRuby support for jsonlint" if RUBY_ENGINE == "jruby") do
    it "detects invalid JSON" do
      expect do |b|
        described_class.new(StringIO.new(%({"a": "b", "a": "c"})), validate: true).each_statement(&b)
      end.to raise_error(RDF::ReaderError)
    end
  end

  context :interface do
    {
      plain: %q({
        "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
         "@id": "_:bnode1",
         "@type": "foaf:Person",
         "foaf:homepage": "http://example.com/bob/",
         "foaf:name": "Bob"
       }),
       leading_comment: %q(
         // A comment before content
         {
           "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@id": "_:bnode1",
            "@type": "foaf:Person",
            "foaf:homepage": "http://example.com/bob/",
            "foaf:name": "Bob"
          }
         ),
       script: %q(<script type="application/ld+json">
         {
           "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@id": "_:bnode1",
            "@type": "foaf:Person",
            "foaf:homepage": "http://example.com/bob/",
            "foaf:name": "Bob"
          }
         </script>),
       script_comments: %q(<script type="application/ld+json">
         // A comment before content
         {
           "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@id": "_:bnode1",
            "@type": "foaf:Person",
            "foaf:homepage": "http://example.com/bob/",
            "foaf:name": "Bob"
          }
         </script>),
    }.each do |variant, src|
      context variant do
        subject {src}

        describe "#initialize" do
          it "yields reader given string" do
            inner = double("inner")
            expect(inner).to receive(:called).with(JSON::LD::Reader)
            JSON::LD::Reader.new(subject) do |reader|
              inner.called(reader.class)
            end
          end

          it "yields reader given IO" do
            inner = double("inner")
            expect(inner).to receive(:called).with(JSON::LD::Reader)
            JSON::LD::Reader.new(StringIO.new(subject)) do |reader|
              inner.called(reader.class)
            end
          end

          it "returns reader" do
            expect(JSON::LD::Reader.new(subject)).to be_a(JSON::LD::Reader)
          end
        end

        describe "#each_statement" do
          it "yields statements" do
            inner = double("inner")
            expect(inner).to receive(:called).with(RDF::Statement).exactly(3)
            JSON::LD::Reader.new(subject).each_statement do |statement|
              inner.called(statement.class)
            end
          end
        end

        describe "#each_triple" do
          it "yields statements" do
            inner = double("inner")
            expect(inner).to receive(:called).exactly(3)
            JSON::LD::Reader.new(subject).each_triple do |subject, predicate, object|
              inner.called(subject.class, predicate.class, object.class)
            end
          end
        end
      end
    end
  end
end
