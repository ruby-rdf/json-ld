$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..')))
require 'rdf' # @see http://rubygems.org/gems/rdf

module JSON
  ##
  # **`JSON::LD`** is a JSON-LD plugin for RDF.rb.
  #
  # @example Requiring the `JSON::LD` module
  #   require 'json/ld'
  #
  # @example Parsing RDF statements from a JSON-LD file
  #   JSON::LD::Reader.open("etc/foaf.jld") do |reader|
  #     reader.each_statement do |statement|
  #       puts statement.inspect
  #     end
  #   end
  #
  # @see http://rdf.rubyforge.org/
  # @see http://www.w3.org/TR/REC-rdf-syntax/
  #
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  module LD
    require 'json'
    require 'json/ld/extensions'
    require 'json/ld/format'
    autoload :Reader,  'json/ld/reader'
    autoload :VERSION, 'json/ld/version'
    autoload :Writer,  'json/ld/writer'
    
    # Default context
    # @see http://json-ld.org/spec/ED/20110507/#the-default-context
    DEFAULT_CONTEXT = {
      "rdf"           => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
      "rdfs"          => "http://www.w3.org/2000/01/rdf-schema#",
      "owl"           => "http://www.w3.org/2002/07/owl#",
      "xsd"           => "http://www.w3.org/2001/XMLSchema#",
      "dcterms"       => "http://purl.org/dc/terms/",
      "foaf"          => "http://xmlns.com/foaf/0.1/",
      "cal"           => "http://www.w3.org/2002/12/cal/ical#",
      "vcard"         => "http://www.w3.org/2006/vcard/ns# ",
      "geo"           => "http://www.w3.org/2003/01/geo/wgs84_pos#",
      "cc"            => "http://creativecommons.org/ns#",
      "sioc"          => "http://rdfs.org/sioc/ns#",
      "doap"          => "http://usefulinc.com/ns/doap#",
      "com"           => "http://purl.org/commerce#",
      "ps"            => "http://purl.org/payswarm#",
      "gr"            => "http://purl.org/goodrelations/v1#",
      "sig"           => "http://purl.org/signature#",
      "ccard"         => "http://purl.org/commerce/creditcard#",
      "@coerce"       => {
        # Note: rdf:type is not in the document, but necessary for this implementation
        "xsd:anyURI"  => ["rdf:type", "rdf:rest", "foaf:homepage", "foaf:member"],
        "xsd:integer" => "foaf:age",
      }
    }.freeze

    # Default type coercion, in property => datatype order
    DEFAULT_COERCE = {
      RDF.type           => RDF::XSD.anyURI,
      RDF.first          => false,            # Make sure @coerce isn't generated for this
      RDF.rest           => RDF::XSD.anyURI,
      RDF::FOAF.homepage => RDF::XSD.anyURI,
      RDF::FOAF.member   => RDF::XSD.anyURI,
      RDF::FOAF.age      => RDF::XSD.integer,
    }.freeze

    def self.debug?; @debug; end
    def self.debug=(value); @debug = value; end
  end
end