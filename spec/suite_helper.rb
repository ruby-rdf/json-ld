require 'json/ld'
require 'open-uri'
require 'support/extensions'

# For now, override RDF::Utils::File.open_file to look for the file locally before attempting to retrieve it
module RDF::Util
  module File
    REMOTE_PATH = "http://json-ld.org/test-suite/"
    LOCAL_PATH = ::File.expand_path("../json-ld.org/test-suite", __FILE__) + '/'

    ##
    # Override to use Patron for http and https, Kernel.open otherwise.
    #
    # @param [String] filename_or_url to open
    # @param  [Hash{Symbol => Object}] options
    # @option options [Array, String] :headers
    #   HTTP Request headers.
    # @return [IO] File stream
    # @yield [IO] File stream
    def self.open_file(filename_or_url, options = {}, &block)
      case filename_or_url.to_s
      when /^file:/
        path = filename_or_url[5..-1]
        Kernel.open(path.to_s, &block)
      when /^#{REMOTE_PATH}/
        begin
          #puts "attempt to open #{filename_or_url} locally"
          local_filename = filename_or_url.to_s.sub(REMOTE_PATH, LOCAL_PATH)
          if ::File.exist?(local_filename)
            response = ::File.open(local_filename)
            #puts "use #{filename_or_url} locally"
            case filename_or_url.to_s
            when /\.jsonld$/
              def response.content_type; 'application/ld+json'; end
            when /\.sparql$/
              def response.content_type; 'application/sparql-query'; end
            end
            response.instance_variable_set(:@base_uri, filename_or_url)
            def response.base_uri; @base_uri; end

            if block_given?
              begin
                yield response
              ensure
                response.close
              end
            else
              response
            end
          else
            Kernel.open(filename_or_url.to_s, &block)
          end
        rescue Errno::ENOENT #, OpenURI::HTTPError
          # Not there, don't run tests
          StringIO.new("")
        end
      else
        Kernel.open(filename_or_url.to_s, &block)
      end
    end
  end
end

module Fixtures
  module SuiteTest
    SUITE = RDF::URI("http://json-ld.org/test-suite/")

    class Manifest < JSON::LD::Resource
      def self.open(file)
        #puts "open: #{file}"
        RDF::Util::File.open_file(file) do |f|
          json = JSON.parse(f.read)
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
          opts = {}
          {'processingMode' => "json-ld-1.0"}.merge(property('option') || {}).each do |k, v|
            opts[k.to_sym] = v
          end
          opts
        end
      end

      # Alias input, context, expect and frame
      %w(input context expect frame).each do |m|
        define_method(m.to_sym) {property(m) && RDF::Util::File.open_file("#{SUITE}tests/#{property(m)}")}
        define_method("#{m}_loc".to_sym) {property(m) && "#{SUITE}tests/#{property(m)}"}
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
        debug = ["test: #{inspect}", "source: #{input.read}"]
        debug << "context: #{context.read}" if context
        debug << "options: #{options.inspect}" unless options.empty?
        debug << "context: #{frame.read}" if frame

        if positiveTest?
          debug << "expected: #{expect}" if expect
          begin
            result = case testType
            when "jld:ExpandTest"
              JSON::LD::API.expand(input_loc, options.merge(:debug => debug))
            when "jld:CompactTest"
              JSON::LD::API.compact(input_loc, context_loc, options.merge(:debug => debug))
            when "jld:FlattenTest"
              JSON::LD::API.flatten(input_loc, context_loc, options.merge(:debug => debug))
            when "jld:FrameTest"
              JSON::LD::API.frame(input_loc, frame_loc, options.merge(:debug => debug))
            when "jld:FromRDFTest"
              repo = RDF::Repository.new << RDF::NQuads::Reader.new(input)
              debug << "repo: #{repo.dump(id == '#t0012' ? :nquads : :trig)}"
              JSON::LD::API.fromRDF(repo, options.merge(:debug => debug))
            when "jld:ToRDFTest"
              JSON::LD::API.toRDF(input_loc, options.merge(:debug => debug)).map do |statement|
                to_quad(statement)
              end
            else
              fail("Unknown test type: #{testType}")
            end
            if evaluationTest?
              if testType == "jld:ToRDFTest"
                sorted_expected = expect.readlines.uniq.sort.join("")
                rspec_example.instance_eval {
                  expect(result.uniq.sort.join("")).to produce(sorted_expected, debug)
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
          rescue JSON::LD::JsonLdError => e
            fail("Invalid Context: #{e.message}")
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
                  JSON::LD::API.expand(t.input, t.options.merge(:debug => debug))
                when "jld:CompactTest"
                  JSON::LD::API.compact(t.input, t.context, t.options.merge(:debug => debug))
                when "jld:FlattenTest"
                  JSON::LD::API.flatten(t.input, t.context, t.options.merge(:debug => debug))
                when "jld:FrameTest"
                  JSON::LD::API.frame(t.input, t.frame, t.options.merge(:debug => debug))
                when "jld:FromRDFTest"
                  repo = RDF::Repository.load(t.input)
                  debug << "repo: #{repo.dump(id == '#t0012' ? :nquads : :trig)}"
                  JSON::LD::API.fromRDF(repo, t.options.merge(:debug => debug))
                when "jld:ToRDFTest"
                  JSON::LD::API.toRDF(t.input, t.options.merge(:debug => debug)).map do |statement|
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
  end
end
