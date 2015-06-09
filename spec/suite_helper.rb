require 'json/ld'
require 'support/extensions'

module Fixtures
  module SuiteTest
    SUITE = RDF::URI("http://json-ld.org/test-suite/")
    #SUITE = RDF::URI("http://localhost/~gregg/json-ld.org/test-suite/")

    class Manifest < JSON::LD::Resource
      def self.open(file)
        #puts "open: #{file}"
        Fixtures::SuiteTest.documentLoader(file) do |remote|
          json = JSON.parse(remote.document)
          if block_given?
            yield self.from_jsonld(json)
          else
            self.from_jsonld(json)
          end
        end
      end

      # @param [Hash] json framed JSON-LD
      # @return [Array<Manifest>]
      def self.from_jsonld(json)
        Manifest.new(json)
      end

      def entries
        # Map entries to resources
        attributes['sequence'].map do |e|
          e.is_a?(String) ? Manifest.open("#{SUITE}#{e}") : Entry.new(e)
        end
      end
    end

    class Entry < JSON::LD::Resource
      attr_accessor :debug

      # Base is expanded input file
      def base
        options.fetch('base', "#{SUITE}tests/#{property('input')}")
      end

      def options
        @options ||= begin
          opts = {documentLoader: Fixtures::SuiteTest.method(:documentLoader)}
          {'processingMode' => "json-ld-1.0"}.merge(property('option') || {}).each do |k, v|
            opts[k.to_sym] = v
          end
          opts
        end
      end

      # Alias input, context, expect and frame
      %w(input context expect frame).each do |m|
        define_method(m.to_sym) do
          return nil unless property(m)
          res = nil
          Fixtures::SuiteTest.documentLoader("#{SUITE}tests/#{property(m)}", safe: true) do |remote_doc|
            res = remote_doc.document
          end
          res
        end

        define_method("#{m}_loc".to_sym) {property(m) && "#{SUITE}tests/#{property(m)}"}

        define_method("#{m}_json".to_sym) do
          JSON.parse(self.send(m)) if property(m)
        end
      end

      def testType
        property('@type').reject {|t| t =~ /EvaluationTest|SyntaxTest/}.first
      end

      def evaluationTest?
        property('@type').to_s.include?('EvaluationTest')
      end

      def positiveTest?
        property('@type').include?('jld:PositiveEvaluationTest')
      end
      
      def trace; @debug.join("\n"); end

      # Execute the test
      def run(rspec_example = nil)
        debug = @debug = ["test: #{inspect}", "source: #{input}"]
        @debug << "context: #{context}" if context_loc
        @debug << "options: #{options.inspect}" unless options.empty?
        @debug << "frame: #{frame}" if frame_loc

        options = if self.options[:useDocumentLoader]
          self.options.merge(documentLoader: Fixtures::SuiteTest.method(:documentLoader))
        else
          self.options.dup
        end

        if positiveTest?
          @debug << "expected: #{expect rescue nil}" if expect_loc
          begin
            result = case testType
            when "jld:ExpandTest"
              JSON::LD::API.expand(input_loc, options.merge(debug: debug))
            when "jld:CompactTest"
              JSON::LD::API.compact(input_loc, context_json['@context'], options.merge(debug: debug))
            when "jld:FlattenTest"
              JSON::LD::API.flatten(input_loc, context_loc, options.merge(debug: debug))
            when "jld:FrameTest"
              JSON::LD::API.frame(input_loc, frame_loc, options.merge(debug: debug))
            when "jld:FromRDFTest"
              repo = RDF::Repository.load(input_loc, format: :nquads)
              @debug << "repo: #{repo.dump(id == '#t0012' ? :nquads : :trig)}"
              JSON::LD::API.fromRdf(repo, options.merge(debug: debug))
            when "jld:ToRDFTest"
              JSON::LD::API.toRdf(input_loc, options.merge(debug: debug)).map do |statement|
                to_quad(statement)
              end
            else
              fail("Unknown test type: #{testType}")
            end
            if evaluationTest?
              if testType == "jld:ToRDFTest"
                expected = expect
                rspec_example.instance_eval {
                  expect(result.sort.join("")).to produce(expected, debug)
                }
              else
                expected = JSON.load(expect)
                rspec_example.instance_eval {
                  expect(result).to produce(expected, debug)
                }
              end
            else
              rspec_example.instance_eval {
                expect(result).to_not be_nil
              }
            end
          rescue JSON::LD::JsonLdError => e
            fail("Processing error: #{e.message}")
          rescue JSON::LD::InvalidFrame => e
            fail("Invalid Frame: #{e.message}")
          end
        else
          debug << "expected: #{property('expect')}" if property('expect')
          t = self
          rspec_example.instance_eval do
            if t.evaluationTest?
              expect do
                case t.testType
                when "jld:ExpandTest"
                  JSON::LD::API.expand(t.input_loc, options.merge(debug: debug))
                when "jld:CompactTest"
                  JSON::LD::API.compact(t.input_loc, t.context_json['@context'], options.merge(debug: debug))
                when "jld:FlattenTest"
                  JSON::LD::API.flatten(t.input_loc, t.context_loc, options.merge(debug: debug))
                when "jld:FrameTest"
                  JSON::LD::API.frame(t.input_loc, t.frame_loc, options.merge(debug: debug))
                when "jld:FromRDFTest"
                  repo = RDF::Repository.load(t.input_loc)
                  debug << "repo: #{repo.dump(id == '#t0012' ? :nquads : :trig)}"
                  JSON::LD::API.fromRdf(repo, options.merge(debug: debug))
                when "jld:ToRDFTest"
                  JSON::LD::API.toRdf(t.input_loc, options.merge(debug: debug)).map do |statement|
                    t.to_quad(statement)
                  end
                else
                  success("Unknown test type: #{testType}")
                end
              end.to raise_error(/#{t.property('expect')}/)
            else
              fail("No support for NegativeSyntaxTest")
            end
          end
        end
      end

      # Don't use NQuads writer so that we don't escape Unicode
      def to_quad(thing)
        case thing
        when RDF::URI
          thing.canonicalize.to_ntriples
        when RDF::Node
          escaped(thing)
        when RDF::Literal::Double
          thing.canonicalize.to_ntriples
        when RDF::Literal
          v = quoted(escaped(thing.value))
          case thing.datatype
          when nil, "http://www.w3.org/2001/XMLSchema#string", "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"
            # Ignore these
          else
            v += "^^#{to_quad(thing.datatype)}"
          end
          v += "@#{thing.language}" if thing.language
          v
        when RDF::Statement
          thing.to_quad.map {|r| to_quad(r)}.compact.join(" ") + " .\n"
        end
      end

      ##
      # @param  [String] string
      # @return [String]
      def quoted(string)
        "\"#{string}\""
      end

      ##
      # @param  [String, #to_s] string
      # @return [String]
      def escaped(string)
        string.to_s.gsub('\\', '\\\\').gsub("\t", '\\t').
          gsub("\n", '\\n').gsub("\r", '\\r').gsub('"', '\\"')
      end
    end

    REMOTE_PATH = "http://json-ld.org/test-suite/"
    LOCAL_PATH = ::File.expand_path("../json-ld.org/test-suite", __FILE__) + '/'
    ##
    # Document loader to use for tests having `useDocumentLoader` option
    #
    # @param [RDF::URI, String] url
    # @param [Hash<Symbol => Object>] options
    # @option options [Boolean] :validate
    #   Allow only appropriate content types
    # @return [RemoteDocument] retrieved remote document and context information unless block given
    # @yield remote_document
    # @yieldparam [RemoteDocument] remote_document
    # @raise [JsonLdError]
    def documentLoader(url, options = {}, &block)
      remote_document = nil
      options[:headers] ||= JSON::LD::API::OPEN_OPTS[:headers]

      url = url.to_s[5..-1] if url.to_s.start_with?("file:")

      if url.to_s.start_with?(REMOTE_PATH) && ::File.exist?(LOCAL_PATH) && url.to_s !~ /remote-doc/
        #puts "attempt to open #{filename_or_url} locally"
        local_filename = url.to_s.sub(REMOTE_PATH, LOCAL_PATH)
        if ::File.exist?(local_filename)
          remote_document = JSON::LD::API::RemoteDocument.new(url.to_s, ::File.read(local_filename))
          return block_given? ? yield(remote_document) : remote_document
        else
          raise JSON::LD::JsonLdError::LoadingDocumentFailed, "no such file #{local_filename}"
        end
      end

      # don't cache for these specs
      options = options.merge(use_net_http: true) if url.to_s =~ /remote-doc/
      JSON::LD::API.documentLoader(url, options, &block)
    rescue JSON::LD::JsonLdError::LoadingDocumentFailed, JSON::LD::JsonLdError::MultipleContextLinkHeaders
      raise unless options[:safe]
      "don't raise error"
    end
    module_function :documentLoader
  end
end
