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
    
    # Keywords
    BASE     = '@base'.freeze
    COERCE   = '@coerce'.freeze
    CONTEXT  = '@context'.freeze
    DATATYPE = '@datatype'.freeze
    IRI      = '@iri'.freeze
    LANGUAGE = '@language'.freeze
    LITERAL  = '@literal'.freeze
    SUBJECT  = '@subject'.freeze
    TYPE     = '@type'.freeze
    VOCAB    = '@vocab'.freeze
    
    # Default context
    # @see http://json-ld.org/spec/ED/20110507/#the-default-context
    DEFAULT_CONTEXT = {
      '@coerce'       => {
        IRI  => [TYPE]
      }
    }.freeze

    # Default type coercion, in property => datatype order
    DEFAULT_COERCE = {
      TYPE        => IRI
#      RDF.first    => false,            # Make sure @coerce isn't generated for this
#      RDF.rest     => IRI
    }.freeze

    def self.debug?; @debug; end
    def self.debug=(value); @debug = value; end
  end
end