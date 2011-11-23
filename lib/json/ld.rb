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
    autoload :Normalize,  'json/ld/normalize'
    autoload :Reader,     'json/ld/reader'
    autoload :VERSION,    'json/ld/version'
    autoload :Writer,     'json/ld/writer'
    
    # Default context
    # @see http://json-ld.org/spec/ED/20110507/#the-default-context
    DEFAULT_CONTEXT = {
      '@coerce'       => {
        '@iri'          => ['@type']
      }
    }.freeze

    # Default type coercion, in property => datatype order
    DEFAULT_COERCE = {
      '@type'            => '@iri',
      RDF.first.to_s  => false,            # Make sure @coerce isn't generated for this
      RDF.rest.to_s   => '@iri',
    }.freeze


    # Regexp matching an NCName.
    NC_REGEXP = Regexp.new(
      %{^
        (?!\\\\u0301)             # &#x301; is a non-spacing acute accent.
                                  # It is legal within an XML Name, but not as the first character.
        (  [a-zA-Z_]
         | \\\\u[0-9a-fA-F]
        )
        (  [0-9a-zA-Z_\.-]
         | \\\\u([0-9a-fA-F]{4})
        )*
      $},
      Regexp::EXTENDED)

    def self.debug?; @debug; end
    def self.debug=(value); @debug = value; end
  end
end