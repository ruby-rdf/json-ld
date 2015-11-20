module JSON::LD
  ##
  # JSON-LD format specification.
  #
  # @example Obtaining an JSON-LD format class
  #     RDF::Format.for(:jsonld)           #=> JSON::LD::Format
  #     RDF::Format.for("etc/foaf.jsonld")
  #     RDF::Format.for(:file_name         => "etc/foaf.jsonld")
  #     RDF::Format.for(file_extension: "jsonld")
  #     RDF::Format.for(:content_type   => "application/ld+json")
  #
  # @example Obtaining serialization format MIME types
  #     RDF::Format.content_types      #=> {"application/ld+json" => [JSON::LD::Format],
  #                                         "application/x-ld+json" => [JSON::LD::Format]}
  #
  # @example Obtaining serialization format file extension mappings
  #     RDF::Format.file_extensions    #=> {:jsonld => [JSON::LD::Format] }
  #
  # @see http://www.w3.org/TR/json-ld/
  # @see http://json-ld.org/test-suite/
  class Format < RDF::Format
    content_type     'application/ld+json',
                     extension: :jsonld,
                     alias: 'application/x-ld+json'
    content_encoding 'utf-8'

    reader { JSON::LD::Reader }
    writer { JSON::LD::Writer }

    ##
    # Sample detection to see if it matches JSON-LD
    #
    # Use a text sample to detect the format of an input file. Sub-classes implement
    # a matcher sufficient to detect probably format matches, including disambiguating
    # between other similar formats.
    #
    # @param [String] sample Beginning several bytes (~ 1K) of input.
    # @return [Boolean]
    def self.detect(sample)
      !!sample.match(/\{\s*"@(id|context|type)"/m) &&
        # Exclude CSVW metadata
        !sample.include?("http://www.w3.org/ns/csvw")
    end
    
    ##
    # Override normal symbol generation
    def self.to_sym
      :jsonld
    end

    ##
    # Override normal format name
    def self.name
      "JSON-LD"
    end
  end
end
