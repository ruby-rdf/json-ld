$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..')))
require 'rdf' # @see http://rubygems.org/gems/rdf

module JSON
  ##
  # **`JSON::LD`** is a JSON-LD extension for RDF.rb.
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
    autoload :Context,            'json/ld/context'
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
      indent:       "  ",
      space:        " ",
      space_before: "",
      object_nl:    "\n",
      array_nl:     "\n"
    )

    def self.debug?; @debug; end
    def self.debug=(value); @debug = value; end
    
    class JsonLdError < Exception
      def to_s
        "#{self.class.instance_variable_get :@code}: #{super}"
      end
      def code
        self.class.instance_variable_get :@code
      end

      class LoadingDocumentFailed < JsonLdError; @code = "loading document failed"; end
      class ListOfLists < JsonLdError; @code = "list of lists"; end
      class InvalidIndexValue < JsonLdError; @code = "invalid @index value"; end
      class ConflictingIndexes < JsonLdError; @code = "conflicting indexes"; end
      class InvalidIdValue < JsonLdError; @code = "invalid @id value"; end
      class InvalidLocalContext < JsonLdError; @code = "invalid local context"; end
      class MultipleContextLinkHeaders < JsonLdError; @code = "multiple context link headers"; end
      class LoadingRemoteContextFailed < JsonLdError; @code = "loading remote context failed"; end
      class InvalidRemoteContext < JsonLdError; @code = "invalid remote context"; end
      class RecursiveContextInclusion < JsonLdError; @code = "recursive context inclusion"; end
      class InvalidBaseIRI < JsonLdError; @code = "invalid base IRI"; end
      class InvalidVocabMapping < JsonLdError; @code = "invalid vocab mapping"; end
      class InvalidDefaultLanguage < JsonLdError; @code = "invalid default language"; end
      class KeywordRedefinition < JsonLdError; @code = "keyword redefinition"; end
      class InvalidTermDefinition < JsonLdError; @code = "invalid term definition"; end
      class InvalidReverseProperty < JsonLdError; @code = "invalid reverse property"; end
      class InvalidIRIMapping < JsonLdError; @code = "invalid IRI mapping"; end
      class CyclicIRIMapping < JsonLdError; @code = "cyclic IRI mapping"; end
      class InvalidKeywordAlias < JsonLdError; @code = "invalid keyword alias"; end
      class InvalidTypeMapping < JsonLdError; @code = "invalid type mapping"; end
      class InvalidLanguageMapping < JsonLdError; @code = "invalid language mapping"; end
      class CollidingKeywords < JsonLdError; @code = "colliding keywords"; end
      class InvalidContainerMapping < JsonLdError; @code = "invalid container mapping"; end
      class InvalidTypeValue < JsonLdError; @code = "invalid type value"; end
      class InvalidValueObject < JsonLdError; @code = "invalid value object"; end
      class InvalidValueObjectValue < JsonLdError; @code = "invalid value object value"; end
      class InvalidLanguageTaggedString < JsonLdError; @code = "invalid language-tagged string"; end
      class InvalidLanguageTaggedValue < JsonLdError; @code = "invalid language-tagged value"; end
      class InvalidTypedValue < JsonLdError; @code = "invalid typed value"; end
      class InvalidSetOrListObject < JsonLdError; @code = "invalid set or list object"; end
      class InvalidLanguageMapValue < JsonLdError; @code = "invalid language map value"; end
      class CompactionToListOfLists < JsonLdError; @code = "compaction to list of lists"; end
      class InvalidReversePropertyMap < JsonLdError; @code = "invalid reverse property map"; end
      class InvalidReverseValue < JsonLdError; @code = "invalid @reverse value"; end
      class InvalidReversePropertyValue < JsonLdError; @code = "invalid reverse property value"; end
    end
    
    class InvalidFrame < Exception
      class MultipleEmbeds < InvalidFrame; end
      class Syntax < InvalidFrame; end
    end
  end
end