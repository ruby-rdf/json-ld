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
  #     RDF::Format.for(:file_extension => "json")
  #     RDF::Format.for(:file_extension => "ld")
  #     RDF::Format.for(:content_type   => "application/json")
  #
  # @example Obtaining serialization format MIME types
  #     RDF::Format.content_types      #=> {"application/json" => [JSON::LD::Format]}
  #
  # @example Obtaining serialization format file extension mappings
  #     RDF::Format.file_extensions    #=> {:json => "application/json"}
  #
  # @see http://www.w3.org/TR/rdf-testcases/#ntriples
  class Format < RDF::Format
    content_type     'application/json',    :extension => :json
    content_type     'application/json',    :extension => :ld
    content_encoding 'utf-8'

    reader { JSON::LD::Reader }
    writer { JSON::LD::Writer }
  end
  
  # Alias for JSON-LD format
  #
  # This allows the following:
  #
  # @example Obtaining an Notation3 format class
  #     RDF::Format.for(:jsonld)         #=> JSON::LD::JSONLD
  #     RDF::Format.for(:jsonld).reader  #=> JSON::LD::Reader
  #     RDF::Format.for(:jsonld).writer  #=> JSON::LD::Writer
  class JSONLD < RDF::Format
    content_type     'application/json',    :extension => :jsonld
    content_encoding 'utf-8'

    reader { JSON::LD::Reader }
    writer { JSON::LD::Writer }
  end
end
