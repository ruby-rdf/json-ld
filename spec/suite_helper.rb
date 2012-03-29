# Spira class for manipulating test-manifest style test suites.
# Used for SWAP tests
require 'spira'
require 'json/ld'
require 'open-uri'

require 'rdf/turtle'


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
        #puts "attempt to open #{filename_or_url} locally"
        if response = ::File.open(filename_or_url.to_s.sub(REMOTE_PATH, LOCAL_PATH))
          #puts "use #{filename_or_url} locally"
          case filename_or_url.to_s
          when /\.jsonld$/
            def response.content_type; 'application/ld+json'; end
          when /\.sparql$/
            def response.content_type; 'application/sparql-query'; end
          end

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
      else
      end
    end
  end
end

module Fixtures
  module JSONLDTest
    SUITE = RDF::URI("http://json-ld.org/test-suite/")
    class Test < RDF::Vocabulary("http://www.w3.org/2006/03/test-description#"); end
    class Jld < RDF::Vocabulary("http://json-ld.org/test-suite/vocab#"); end

    class Manifest < Spira::Base
      type Jld.Manifest
      property :name,       :predicate => DC11.title,         :type => XSD.string
      property :comment,    :predicate => RDF::RDFS.comment,  :type => XSD.string
      property :sequence,   :predicate => Jld.sequence
      
      def entries
        repo = self.class.repository
        RDF::List.new(sequence, repo).map do |entry|
          results = repo.query(:subject => entry, :predicate => RDF.type)
          entry_types = results.map(&:object)

          # Load entry if it is not in repo
          if entry_types.empty?
            repo.load(entry, :format => :jsonld)
            entry_types = repo.query(:subject => entry, :predicate => RDF.type).map(&:object)
          end
          
          case 
          when entry_types.include?(Jld.Manifest) then entry.as(Manifest)
          when entry_types.include?(Jld.CompactTest) then entry.as(CompactTest)
          when entry_types.include?(Jld.ExpandTest) then entry.as(ExpandTest)
          when entry_types.include?(Jld.FrameTest) then entry.as(FrameTest)
          when entry_types.include?(Jld.NormalizeTest) then entry.as(NormalizeTest)
          when entry_types.include?(Jld.RDFTest) then entry.as(RDFTest)
          when entry_types.include?(Test.TestCase) then entry.as(Entry)
          else raise "Unexpected entry type: #{entry_types.inspect}"
          end
        end
      end
      
      def inspect
        "[#{self.class.to_s} " + %w(
          subject
          name
        ).map {|a| v = self.send(a); "#{a}='#{v}'" if v}.compact.join(", ") +
        ", entries=#{entries.length}" +
        "]"
      end
    end

    class Entry
      attr_accessor :debug
      include Spira::Resource
      type Test.TestCase

      property :name,           :predicate => DC11.title,                   :type => XSD.string
      property :purpose,        :predicate => Test.purpose,                 :type => XSD.string
      property :expected,       :predicate => Test.expectedResults
      property :inputDocument,  :predicate => Test.informationResourceInput
      property :resultDocument, :predicate => Test.informationResourceResults
      property :extraDocument,  :predicate => Test.input

      def information; name; end

      def input
        RDF::Util::File.open_file(self.inputDocument)
      end

      def extra
        RDF::Util::File.open_file(self.extraDocument)
      end
      
      def expect
        self.resultDocument ? RDF::Util::File.open_file(self.resultDocument) : ""
      end

      def base_uri
        inputDocument.to_s
      end
      
      def trace
        @debug.to_a.join("\n")
      end

      def inspect
        "[#{self.class.to_s} " + %w(
          subject
          name
          inputDocument
          resultDocument
          extraDocument
        ).map {|a| v = self.send(a); "#{a}='#{v}'" if v}.compact.join(", ") +
        "]"
      end
    end

    class CompactTest < Entry
      type Jld.CompactTest
    end

    class ExpandTest < Entry
      type Jld.ExpandTest
    end

    class FrameTest < Entry
      type Jld.FameTest
    end

    class NormalizeTest < Entry
      type Jld.NormalizeTest
    end

    class RDFTest < Entry
      type Jld.RDFTest
      
      def expectedResults
         RDF::Literal::Boolean.new(true)
      end

      def sparql
        Kernel.open(self.expected) if self.expected
      end
    end

    repo = RDF::Repository.load(SUITE.join("manifest.jsonld"), :format => :jsonld)
    Spira.add_repository! :default, repo
    puts Manifest.each.to_a.first.inspect
  end
end
