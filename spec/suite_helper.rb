# Spira class for manipulating test-manifest style test suites.
# Used for SWAP tests
require 'spira'
require 'rdf/n3'
require 'open-uri'

module Fixtures
  SUITE = RDF::URI("http://json-ld.org/test-suite/")

  class TestCase
    HTMLRE = Regexp.new('([0-9]{4,4})\.xhtml')
    TCPATHRE = Regexp.compile('\$TCPATH')

    class Test < RDF::Vocabulary("http://www.w3.org/2006/03/test-description#"); end

    attr_accessor :debug
    include Spira::Resource

    type Test.TestCase
    property :title,          :predicate => DC11.title,                   :type => XSD.string
    property :purpose,        :predicate => Test.purpose,                 :type => XSD.string
    property :expected,       :predicate => Test.expectedResults
    property :contributor,    :predicate => DC11.contributor,             :type => XSD.string
    property :reference,      :predicate => Test.specificationRefference, :type => XSD.string
    property :classification, :predicate => Test.classification
    property :inputDocument,  :predicate => Test.informationResourceInput
    property :resultDocument, :predicate => Test.informationResourceResults

    def self.for_specific(classification = nil)
      each do |tc|
        yield(tc) if (classification.nil? || tc.classification == classification)
      end
    end
    
    def expectedResults
      RDF::Literal::Boolean.new(expected.nil? ? "true" : expected)
    end
    
    def name
      subject.to_s.split("/").last
    end

    def trace
      @debug.to_a.join("\n")
    end
    
    def inspect
      "[#{self.class.to_s} " + %w(
        title
        classification
        inputDocument
        resultDocument
      ).map {|a| v = self.send(a); "#{a}='#{v}'" if v}.compact.join(", ") +
      "]"
    end
  end

  local_manifest = File.join(File.expand_path(File.dirname(__FILE__)), 'json-ld-test-suite', 'manifest.ttl')
  repo = if File.exist?(local_manifest)
    RDF::Repository.load(local_manifest, :base_uri => SUITE.join("manifest.ttl"), :format => :n3)
  else
    RDF::Repository.load(SUITE.join("manifest.ttl"), :format => :n3)
  end
  Spira.add_repository! :default, repo
end

# For now, override OpenURI.open_uri to look for the file locally before attempting to retrieve it
module OpenURI
  class << self
    REMOTE_PATH = Fixtures::SUITE.to_s + "test-cases/"
    LOCAL_PATH = File.expand_path(File.dirname(__FILE__)) + "/json-ld.org/test-suite/tests/"

    alias open_uri_without_local open_uri #:nodoc:
    def open_uri(uri, *rest, &block)
      if uri.to_s.index(REMOTE_PATH) == 0 && response = File.open(uri.to_s.sub(REMOTE_PATH, LOCAL_PATH))
        case uri
        when /\.json$/
          def response.content_type; 'application/json'; end
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
