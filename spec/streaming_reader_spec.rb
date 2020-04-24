# coding: utf-8
require_relative 'spec_helper'
require 'rdf/spec/reader'

describe JSON::LD::Reader do
  let!(:doap) {File.expand_path("../../etc/doap.jsonld", __FILE__)}
  let!(:doap_nt) {File.expand_path("../../etc/doap.nt", __FILE__)}
  let!(:doap_count) {File.open(doap_nt).each_line.to_a.length}
  let(:logger) {RDF::Spec.logger}

  after(:each) {|example| puts logger.to_s if example.exception}

  it_behaves_like 'an RDF::Reader' do
    let(:reader_input) {File.read(doap)}
    let(:reader) {JSON::LD::Reader.new(reader_input, stream: true)}
    let(:reader_count) {doap_count}
  end

  context "when validating", pending: ("JRuby support for jsonlint" if RUBY_ENGINE == "jruby") do
    it "detects invalid JSON" do
      expect do |b|
        described_class.new(StringIO.new(%({"a": "b", "a": "c"})), validate: true, logger: false).each_statement(&b)
      end.to raise_error(RDF::ReaderError)
    end
  end

  context :interface do
    {
      plain: %q({
        "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
        "@type": "foaf:Person",
        "@id": "_:bnode1",
        "foaf:homepage": "http://example.com/bob/",
        "foaf:name": "Bob"
      }),
      leading_comment: %q(
      // A comment before content
      {
        "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
        "@type": "foaf:Person",
        "@id": "_:bnode1",
        "foaf:homepage": "http://example.com/bob/",
        "foaf:name": "Bob"
      }),
      script: %q(<script type="application/ld+json">
      {
        "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
        "@type": "foaf:Person",
        "@id": "_:bnode1",
        "foaf:homepage": "http://example.com/bob/",
        "foaf:name": "Bob"
      }
      </script>),
      script_comments: %q(<script type="application/ld+json">
      // A comment before content
      {
        "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
        "@type": "foaf:Person",
        "@id": "_:bnode1",
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
            JSON::LD::Reader.new(subject, stream: true) do |reader|
              inner.called(reader.class)
            end
          end

          it "yields reader given IO" do
            inner = double("inner")
            expect(inner).to receive(:called).with(JSON::LD::Reader)
            JSON::LD::Reader.new(StringIO.new(subject), stream: true) do |reader|
              inner.called(reader.class)
            end
          end

          it "returns reader" do
            expect(JSON::LD::Reader.new(subject, stream: true)).to be_a(JSON::LD::Reader)
          end
        end

        describe "#each_statement" do
          it "yields statements" do
            inner = double("inner")
            expect(inner).to receive(:called).with(RDF::Statement).exactly(3)
            JSON::LD::Reader.new(subject, stream: true).each_statement do |statement|
              inner.called(statement.class)
            end
          end
        end

        describe "#each_triple" do
          it "yields statements" do
            inner = double("inner")
            expect(inner).to receive(:called).exactly(3)
            JSON::LD::Reader.new(subject, stream: true).each_triple do |subject, predicate, object|
              inner.called(subject.class, predicate.class, object.class)
            end
          end
        end
      end
    end
  end

  context "Selected toRdf tests" do
    {
      "e004": {
        input: %({
          "@context": {
            "mylist1": {"@id": "http://example.com/mylist1", "@container": "@list"}
          },
          "@id": "http://example.org/id",
          "mylist1": { "@list": [ ] },
          "http://example.org/list1": { "@list": [ null ] },
          "http://example.org/list2": { "@list": [ {"@value": null} ] }
        }),
        expect: %(
        <http://example.org/id> <http://example.com/mylist1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
        <http://example.org/id> <http://example.org/list1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
        <http://example.org/id> <http://example.org/list2> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
        )
      },
      "e015": {
        input: %({
          "@context": {
            "myset2": {"@id": "http://example.com/myset2", "@container": "@set" }
          },
          "@id": "http://example.org/id",
          "myset2": [ [], { "@set": [ null ] }, [ null ] ]
        }),
        expect: %(
        )
      },
      "in06": {
        input: %({
          "@context": {
            "@version": 1.1,
            "@vocab": "http://example.org/vocab#",
            "@base": "http://example.org/base/",
            "id": "@id",
            "type": "@type",
            "data": "@nest",
            "links": "@nest",
            "relationships": "@nest",
            "self": {"@type": "@id"},
            "related": {"@type": "@id"}
          },
          "data": [{
            "type": "articles",
            "id": "1",
            "author": {
              "data": { "type": "people", "id": "9" }
            }
          }]
        }),
        expect: %(
        <http://example.org/base/1> <http://example.org/vocab#author> <http://example.org/base/9> .
        <http://example.org/base/1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#articles> .
        <http://example.org/base/9> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#people> .
        ),
        pending: "@nest defining @id"
      }
    }.each do |name, params|
      it name do
        run_to_rdf params
      end
    end
  end

  describe "test suite" do
    require_relative 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::STREAM_SUITE}stream-toRdf-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('@id')}: #{t.name}#{' (negative test)' unless t.positiveTest?}" do
          pending "Generalized RDF" if t.options[:produceGeneralizedRdf]
          pending "@nest defining @id" if %w(#tin06).include?(t.property('@id'))
          pending "double @reverse" if %w(#te043).include?(t.property('@id'))
          pending "graph map containing named graph" if %w(#te084 #te087 #te098 #te101 #te105 #te106).include?(t.property('@id'))
          pending "named graphs" if %w(#t0029 #te021).include?(t.property('@id'))

          pending "scoped contexts" if %w(#tc023 #tc024 #tc032).include?(t.property('@id'))

          if %w(#t0118).include?(t.property('@id'))
            expect {t.run self}.to write(/Statement .* is invalid/).to(:error)
          elsif %w(#twf07).include?(t.property('@id'))
            expect {t.run self}.to write(/skipping graph statement within invalid graph name/).to(:error)
          elsif %w(#te075).include?(t.property('@id'))
            expect {t.run self}.to write(/is invalid/).to(:error)
          elsif %w(#te005 #tpr34 #tpr35 #tpr36 #tpr37 #tpr38 #tpr39 #te119 #te120).include?(t.property('@id'))
            expect {t.run self}.to write("beginning with '@' are reserved for future use").to(:error)
          elsif %w(#te068).include?(t.property('@id'))
            expect {t.run self}.to write("[DEPRECATION]").to(:error)
          elsif %w(#twf05).include?(t.property('@id'))
            expect {t.run self}.to write("@language must be valid BCP47").to(:error)
          else
            expect {t.run self}.not_to write.to(:error)
          end
        end
      end
    end
  end unless ENV['CI']

  def run_to_rdf(params)
    input = params[:input]
    logger.info("input: #{input}")
    output = RDF::Repository.new
    if params[:expect]
      RDF::NQuads::Reader.new(params[:expect], validate: false) {|r| output << r}
      logger.info("expect (quads): #{output.dump(:nquads, validate: false)}")
    else
      logger.info("expect: #{Regexp.new params[:exception]}")
    end
    
    graph = params[:graph] || RDF::Repository.new
    pending params.fetch(:pending, "test implementation") if !input || params[:pending]
    if params[:exception]
      expect do |b|
        JSON::LD::Reader.new(input, stream: true, validate: true, logger: false, **params).each_statement(&b)
      end.to raise_error {|er| expect(er.message).to include params[:exception]}
    else
      if params[:write]
        expect{JSON::LD::Reader.new(input, stream: true, logger: logger, **params) {|st| graph << st}}.to write(params[:write]).to(:error)
      else
        expect{JSON::LD::Reader.new(input, stream: true, logger: logger, **params) {|st| graph << st}}.not_to write.to(:error)
      end
      logger.info("results (quads): #{graph.dump(:nquads, validate: false)}")
      expect(graph).to be_equivalent_graph(output, logger: logger, inputDocument: input)
    end
  end
end
