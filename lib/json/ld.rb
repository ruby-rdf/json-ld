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
      def to_s
        "#{self.class.instance_variable_get :@base_message}: #{super}"
      end
      class LoadingDocumentFailed < ProcessingError; @base_message = "loading document failed"; end
      class ListOfLists < ProcessingError; @base_message = "list of lists"; end
      class InvalidIndexValue < ProcessingError; @base_message = "invalid @index value"; end
      class ConflictingIndexes < ProcessingError; @base_message = "conflicting indexes"; end
      class InvalidIdValue < ProcessingError; @base_message = "invalid @id value"; end
      class InvalidLocalContext < ProcessingError; @base_message = "invalid local context"; end
      class MultipleContextLinkHeaders < ProcessingError; @base_message = "multiple context link headers"; end
      class LoadingRemoteContextFailed < ProcessingError; @base_message = "loading remote context failed"; end
      class InvalidRemoteContext < ProcessingError; @base_message = "invalid remote context"; end
      class RecursiveContextInclusion < ProcessingError; @base_message = "recursive context inclusion"; end
      class InvalidBaseIRI < ProcessingError; @base_message = "invalid base IRI"; end
      class InvalidVocabMapping < ProcessingError; @base_message = "invalid vocab mapping"; end
      class InvalidDefaultLanguage < ProcessingError; @base_message = "invalid default language"; end
      class KeywordRedefinition < ProcessingError; @base_message = "keyword redefinition"; end
      class InvalidTermDefinition < ProcessingError; @base_message = "invalid term definition"; end
      class InvalidReverseProperty < ProcessingError; @base_message = "invalid reverse property"; end
      class InvalidIRIMapping < ProcessingError; @base_message = "invalid IRI mapping"; end
      class CyclicIRIMapping < ProcessingError; @base_message = "cyclic IRI mapping"; end
      class InvalidKeywordAlias < ProcessingError; @base_message = "invalid keyword alias"; end
      class InvalidTypeMapping < ProcessingError; @base_message = "invalid type mapping"; end
      class InvalidLanguageMapping < ProcessingError; @base_message = "invalid language mapping"; end
      class CollidingKeywords < ProcessingError; @base_message = "colliding keywords"; end
      class InvalidContainerMapping < ProcessingError; @base_message = "invalid container mapping"; end
      class InvalidTypeValue < ProcessingError; @base_message = "invalid type value"; end
      class InvalidValueObject < ProcessingError; @base_message = "invalid value object"; end
      class InvalidValueObjectValue < ProcessingError; @base_message = "invalid value object value"; end
      class InvalidLanguageTaggedString < ProcessingError; @base_message = "invalid language-tagged string"; end
      class InvalidLanguageTaggedValue < ProcessingError; @base_message = "invalid language-tagged value"; end
      class InvalidTypedValue < ProcessingError; @base_message = "invalid typed value"; end
      class InvalidSetOrListObject < ProcessingError; @base_message = "invalid set or list object"; end
      class InvalidLanguageMapValue < ProcessingError; @base_message = "invalid language map value"; end
      class CompactionToListOfLists < ProcessingError; @base_message = "compaction to list of lists"; end
      class InvalidReversePropertyMap < ProcessingError; @base_message = "invalid reverse property map"; end
      class InvalidReverseValue < ProcessingError; @base_message = "invalid @reverse value"; end
      class InvalidReversePropertyValue < ProcessingError; @base_message = "invalid reverse property value"; end
    end
    
    class InvalidFrame < Exception
      class MultipleEmbeds < InvalidFrame; end
      class Syntax < InvalidFrame; end
    end
  end
end