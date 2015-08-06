module JSON::LD
  ##
  # RDFa format specification.
  #
  # @example Obtaining an Notation3 format class
  #     RDF::Format.for(:json)            #=> JSON::LD::Format
  #     RDF::Format.for(:ld)              #=> JSON::LD::Format
  #     RDF::Format.for("etc/foaf.json")
  #     RDF::Format.for("etc/foaf.ld")
  #     RDF::Format.for(:file_name      => "etc/foaf.json")
  #     RDF::Format.for(:file_name      => "etc/foaf.ld")
  #     RDF::Format.for(file_extension: "json")
  #     RDF::Format.for(file_extension: "ld")
  #     RDF::Format.for(:content_type   => "application/json")
  #
  # @example Obtaining serialization format MIME types
  #     RDF::Format.content_types      #=> {"application/json" => [JSON::LD::Format]}
  #
  # @example Obtaining serialization format file extension mappings
  #     RDF::Format.file_extensions    #=> {json: "application/json"}
  #
  # @see http://www.w3.org/TR/rdf-testcases/#ntriples
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
