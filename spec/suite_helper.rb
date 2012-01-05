# Spira class for manipulating test-manifest style test suites.
# Used for SWAP tests
require 'spira'
require 'json/ld'
require 'open-uri'

require 'rdf/turtle'

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
            repo.load(entry, :context => entry, :format => :jsonld)
            entry_types = repo.query(:subject => entry, :predicate => RDF.type).map(&:object)
          end
          
          case 
          when entry_types.include?(Jld.Manifest) then entry.as(Manifest)
          when entry_types.include?(Jld.RDFTest) then entry.as(RDFTest)
          when entry_types.include?(Test.TestCase) then entry.as(Entry)
          else raise "Unexpected entry type: #{entry_typess.inpsect}"
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

      def information; name; end

      def input
        Kernel.open(self.inputDocument)
      end
      
      def expect
        self.resultDocument ? Kernel.open(self.resultDocument) : ""
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
        ).map {|a| v = self.send(a); "#{a}='#{v}'" if v}.compact.join(", ") +
        "]"
      end
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

    local_manifest = File.expand_path("../json-ld.org/test-suite/manifest.jsonld", __FILE__)
    repo = if File.exist?(local_manifest)
      RDF::Repository.load(local_manifest, :base_uri => SUITE.join("manifest.jsonld"), :format => :jsonld)
    else
      RDF::Repository.load(SUITE.join("manifest.jsonld"), :format => :jsonld)
    end
    Spira.add_repository! :default, repo
  end
end

# For now, override OpenURI.open_uri to look for the file locally before attempting to retrieve it
module OpenURI
  class << self
    REMOTE_PATH = Fixtures::JSONLDTest::SUITE.to_s
    LOCAL_PATH = File.expand_path(File.dirname(__FILE__)) + "/json-ld.org/test-suite/"

    alias open_uri_without_local open_uri #:nodoc:
    def open_uri(uri, *rest, &block)
      if uri.to_s.index(REMOTE_PATH) == 0 && response = File.open(uri.to_s.sub(REMOTE_PATH, LOCAL_PATH))
        case uri
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
        open_uri_without_local(uri, *rest, &block)
      end
    end
  end
end
