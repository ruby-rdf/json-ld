# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('ld', __dir__))
require 'rdf' # @see https://rubygems.org/gems/rdf
require 'multi_json'
require 'set'

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
  # @see https://rubygems.org/gems/rdf
  # @see http://www.w3.org/TR/REC-rdf-syntax/
  #
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  module LD
    require 'json'
    require 'json/ld/extensions'
    require 'json/ld/format'
    require 'json/ld/utils'
    autoload :API,                'json/ld/api'
    autoload :ContentNegotiation, 'json/ld/conneg'
    autoload :Context,            'json/ld/context'
    autoload :Normalize,          'json/ld/normalize'
    autoload :Reader,             'json/ld/reader'
    autoload :Resource,           'json/ld/resource'
    autoload :StreamingReader,    'json/ld/streaming_reader'
    autoload :StreamingWriter,    'json/ld/streaming_writer'
    autoload :VERSION,            'json/ld/version'
    autoload :Writer,             'json/ld/writer'

    # JSON-LD profiles
    JSON_LD_NS = 'http://www.w3.org/ns/json-ld#'
    PROFILES = %w[expanded compacted flattened framed].map { |p| JSON_LD_NS + p }.freeze

    # Default context when compacting without one being specified
    DEFAULT_CONTEXT = 'http://schema.org'

    # Acceptable MultiJson adapters
    MUTLI_JSON_ADAPTERS = %i[oj json_gem json_pure ok_json yajl nsjsonseerialization]

    KEYWORDS = Set.new(%w[
                         @annotation
                         @base
                         @container
                         @context
                         @default
                         @direction
                         @embed
                         @explicit
                         @first
                         @graph
                         @id
                         @import
                         @included
                         @index
                         @json
                         @language
                         @list
                         @nest
                         @none
                         @omitDefault
                         @propagate
                         @protected
                         @preserve
                         @requireAll
                         @reverse
                         @set
                         @type
                         @value
                         @version
                         @vocab
                       ]).freeze

    # Regexp matching an NCName.
    NC_REGEXP = Regexp.new(
      %{^
        (?!\\\\u0301)             # &#x301; is a non-spacing acute accent.
                                  # It is legal within an XML Name, but not as the first character.
        (  [a-zA-Z_]
         | \\\\u[0-9a-fA-F]
        )
        (  [0-9a-zA-Z_.-]
         | \\\\u([0-9a-fA-F]{4})
        )*
      $},
      Regexp::EXTENDED
    )

    # Datatypes that are expressed in a native form and don't expand or compact
    NATIVE_DATATYPES = [RDF::XSD.integer.to_s, RDF::XSD.boolean.to_s, RDF::XSD.double.to_s]

    JSON_STATE = JSON::State.new(
      indent:       '  ',
      space:        ' ',
      space_before: '',
      object_nl:    "\n",
      array_nl:     "\n"
    )

    MAX_CONTEXTS_LOADED = 50

    # URI Constants
    RDF_JSON = RDF::URI("#{RDF.to_uri}JSON")
    RDF_DIRECTION = RDF::URI("#{RDF.to_uri}direction")
    RDF_LANGUAGE = RDF::URI("#{RDF.to_uri}language")

    class JsonLdError < StandardError
      def to_s
        "#{self.class.instance_variable_get :@code}: #{super}"
      end

      def code
        self.class.instance_variable_get :@code
      end

      class CollidingKeywords < JsonLdError; @code = 'colliding keywords'; end
      class ConflictingIndexes < JsonLdError; @code = 'conflicting indexes'; end
      class CyclicIRIMapping < JsonLdError; @code = 'cyclic IRI mapping'; end
      class InvalidAnnotation < JsonLdError; @code = 'invalid annotation'; end
      class InvalidBaseIRI < JsonLdError; @code = 'invalid base IRI'; end
      class InvalidContainerMapping < JsonLdError; @code = 'invalid container mapping'; end
      class InvalidContextEntry < JsonLdError; @code = 'invalid context entry'; end
      class InvalidContextNullification < JsonLdError; @code = 'invalid context nullification'; end
      class InvalidDefaultLanguage < JsonLdError; @code = 'invalid default language'; end
      class InvalidIdValue < JsonLdError; @code = 'invalid @id value'; end
      class InvalidIndexValue < JsonLdError; @code = 'invalid @index value'; end
      class InvalidVersionValue < JsonLdError; @code = 'invalid @version value'; end
      class InvalidImportValue < JsonLdError; @code = 'invalid @import value'; end
      class InvalidIncludedValue < JsonLdError; @code = 'invalid @included value'; end
      class InvalidIRIMapping < JsonLdError; @code = 'invalid IRI mapping'; end
      class InvalidJsonLiteral < JsonLdError; @code = 'invalid JSON literal'; end
      class InvalidKeywordAlias < JsonLdError; @code = 'invalid keyword alias'; end
      class InvalidLanguageMapping < JsonLdError; @code = 'invalid language mapping'; end
      class InvalidLanguageMapValue < JsonLdError; @code = 'invalid language map value'; end
      class InvalidLanguageTaggedString < JsonLdError; @code = 'invalid language-tagged string'; end
      class InvalidLanguageTaggedValue < JsonLdError; @code = 'invalid language-tagged value'; end
      class InvalidLocalContext < JsonLdError; @code = 'invalid local context'; end
      class InvalidNestValue < JsonLdError; @code = 'invalid @nest value'; end
      class InvalidPrefixValue < JsonLdError; @code = 'invalid @prefix value'; end
      class InvalidPropagateValue < JsonLdError; @code = 'invalid @propagate value'; end
      class InvalidEmbeddedNode < JsonLdError; @code = 'invalid embedded node'; end
      class InvalidRemoteContext < JsonLdError; @code = 'invalid remote context'; end
      class InvalidReverseProperty < JsonLdError; @code = 'invalid reverse property'; end
      class InvalidReversePropertyMap < JsonLdError; @code = 'invalid reverse property map'; end
      class InvalidReversePropertyValue < JsonLdError; @code = 'invalid reverse property value'; end
      class InvalidReverseValue < JsonLdError; @code = 'invalid @reverse value'; end
      class InvalidScopedContext < JsonLdError; @code = 'invalid scoped context'; end
      class InvalidScriptElement < JsonLdError; @code = 'invalid script element'; end
      class InvalidSetOrListObject < JsonLdError; @code = 'invalid set or list object'; end
      class InvalidStreamingKeyOrder < JsonLdError; @code = 'invalid streaming key order' end
      class InvalidTermDefinition < JsonLdError; @code = 'invalid term definition'; end
      class InvalidBaseDirection < JsonLdError; @code = 'invalid base direction'; end
      class InvalidTypedValue < JsonLdError; @code = 'invalid typed value'; end
      class InvalidTypeMapping < JsonLdError; @code = 'invalid type mapping'; end
      class InvalidTypeValue < JsonLdError; @code = 'invalid type value'; end
      class InvalidValueObject < JsonLdError; @code = 'invalid value object'; end
      class InvalidValueObjectValue < JsonLdError; @code = 'invalid value object value'; end
      class InvalidVocabMapping < JsonLdError; @code = 'invalid vocab mapping'; end
      class IRIConfusedWithPrefix < JsonLdError; @code = 'IRI confused with prefix'; end
      class KeywordRedefinition < JsonLdError; @code = 'keyword redefinition'; end
      class LoadingDocumentFailed < JsonLdError; @code = 'loading document failed'; end
      class LoadingRemoteContextFailed < JsonLdError; @code = 'loading remote context failed'; end
      class ContextOverflow < JsonLdError; @code = 'context overflow'; end
      class MissingIncludedReferent < JsonLdError; @code = 'missing @included referent'; end
      class MultipleContextLinkHeaders < JsonLdError; @code = 'multiple context link headers'; end
      class ProtectedTermRedefinition < JsonLdError; @code = 'protected term redefinition'; end
      class ProcessingModeConflict < JsonLdError; @code = 'processing mode conflict'; end
      class InvalidFrame < JsonLdError; @code = 'invalid frame'; end
      class InvalidEmbedValue < InvalidFrame; @code = 'invalid @embed value'; end
    end
  end
end
