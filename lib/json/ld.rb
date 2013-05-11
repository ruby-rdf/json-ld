$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..')))
require 'rdf' # @see http://rubygems.org/gems/rdf
require 'backports' if RUBY_VERSION < "1.9"

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
  # @see http://rubygems.org/gems/rdf
  # @see http://www.w3.org/TR/REC-rdf-syntax/
  #
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  module LD
    require 'json'
    require 'json/ld/extensions'
    require 'json/ld/format'
    require 'json/ld/utils'
    autoload :API,                'json/ld/api'
    autoload :Context,  'json/ld/context'
    autoload :Normalize,          'json/ld/normalize'
    autoload :Reader,             'json/ld/reader'
    autoload :Resource,           'json/ld/resource'
    autoload :VERSION,            'json/ld/version'
    autoload :Writer,             'json/ld/writer'
    
    # Initial context
    # @see http://json-ld.org/spec/latest/json-ld-api/#appendix-b
    INITIAL_CONTEXT = {
      RDF.type.to_s => {"@type" => "@id"}
    }.freeze

    KEYWORDS = %w(
      @base
      @container
      @context
      @default
      @embed
      @embedChildren
      @explicit
      @id
      @index
      @graph
      @language
      @list
      @omitDefault
      @reverse
      @set
      @type
      @value
      @vocab
    ).freeze

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

    # Datatypes that are expressed in a native form and don't expand or compact
    NATIVE_DATATYPES = [RDF::XSD.integer.to_s, RDF::XSD.boolean.to_s, RDF::XSD.double.to_s]

    JSON_STATE = JSON::State.new(
      :indent       => "  ",
      :space        => " ",
      :space_before => "",
      :object_nl    => "\n",
      :array_nl     => "\n"
    )

    def self.debug?; @debug; end
    def self.debug=(value); @debug = value; end
    
    class ProcessingError < Exception
      class CompactionToListOfLists < ProcessingError; end
      class Conflict < ProcessingError; end
      class ConflictingIndexes < ProcessingError; end
      class InvalidIdValue < ProcessingError; end
      class InvalidIndexValue < ProcessingError; end
      class InvalidLanguageMapValue < ProcessingError; end
      class InvalidLanguageTaggedString < ProcessingError; end
      class InvalidLanguageTaggedValue < ProcessingError; end
      class InvalidReversePropertyMap < ProcessingError; end
      class InvalidReversePropertyValue < ProcessingError; end
      class InvalidReverseValue < ProcessingError; end
      class InvalidSetOrListObject < ProcessingError; end
      class InvalidTypedValue < ProcessingError; end
      class InvalidTypeValue < ProcessingError; end
      class InvalidValueObject < ProcessingError; end
      class InvalidValueObjectValue < ProcessingError; end
      class LanguageMap < ProcessingError; end
      class ListOfLists < ProcessingError; end
      class LoadingDocumentFailed < ProcessingError; end
      class Lossy < ProcessingError; end
    end
    
    class InvalidContext < Exception
      class CollidingKeywords < InvalidContext; end
      class CyclicIRIMapping < InvalidContext; end
      class InvalidBaseIRI < InvalidContext; end
      class InvalidBaseIRI < InvalidContext; end
      class InvalidContainerMapping < InvalidContext; end
      class InvalidDefaultLanguage < InvalidContext; end
      class InvalidIRIMapping < InvalidContext; end
      class InvalidKeywordAlias < InvalidContext; end
      class InvalidLanguageMapping < InvalidContext; end
      class InvalidLocalContext < InvalidContext; end
      class InvalidRemoteContext < InvalidContext; end
      class InvalidReverseProperty < InvalidContext; end
      class InvalidTermDefinition < InvalidContext; end
      class InvalidTypeMapping < InvalidContext; end
      class InvalidVocabMapping < InvalidContext; end
      class KeywordRedefinition < InvalidContext; end
      class LoadingRemoteContextFailed < InvalidContext; end
      class RecursiveContextInclusion < InvalidContext; end
    end
    
    class InvalidFrame < Exception
      class MultipleEmbeds < InvalidFrame; end
      class Syntax < InvalidFrame; end
    end
  end
end