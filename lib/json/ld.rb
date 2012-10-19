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
    autoload :EvaluationContext,  'json/ld/evaluation_context'
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
      @container
      @context
      @id
      @language
      @list
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
      # The compaction would lead to a loss of information, such as a @language value.
      LOSSY_COMPACTION = 1

      # The target datatype specified in the coercion rule and the datatype for the typed literal do not match.
      CONFLICTING_DATATYPES = 2
      
      # A list containing another list was detected.
      LIST_OF_LISTS_DETECTED = 3
      
      attr :code
      
      class Lossy < ProcessingError
        def initialize(*args)
          super
          @code = LOSSY_COMPACTION
        end
      end

      class Conflict < ProcessingError
        def initialize(*args)
          super
          @code = CONFLICTING_DATATYPES
        end
      end

      class ListOfLists < ProcessingError
        def initialize(*args)
          super
          @code = LIST_OF_LISTS_DETECTED
        end
      end
    end
    
    class InvalidContext < Exception
      # A general syntax error was detected in the @context. For example, if a @type key maps to anything
      # other than @id or an absolute IRI, this exception would be raised.
      INVALID_SYNTAX	= 1

      # There was a problem encountered loading a remote context.
      LOAD_ERROR = 2
      
      attr :code
      
      class Syntax < InvalidContext
        def initialize(*args)
          super
          @code = INVALID_SYNTAX
        end
      end

      class LoadError < InvalidContext
        def initialize(*args)
          super
          @code = LOAD_ERROR
        end
      end
    end
    
    class InvalidFrame < Exception
      # A frame must be either an object or an array of objects, if the frame is neither of these types,
      # this exception is thrown.
      INVALID_SYNTAX	= 1

      # A subject IRI was specified in more than one place in the input frame.
      # More than one embed of a given subject IRI is not allowed, and if requested, must result in this exception.
      MULTIPLE_EMBEDS = 2
      
      attr :code

      class Syntax < InvalidFrame
        def initialize(*args)
          super
          @code = INVALID_SYNTAX
        end
      end

      class MultipleEmbeds < InvalidFrame
        def initialize(*args)
          super
          @code = MULTIPLE_EMBEDS
        end
      end
    end
  end
end