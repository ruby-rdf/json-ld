module RDF::N3
  ##
  # RDFa format specification.
  #
  # @example Obtaining an Notation3 format class
  #     RDF::Format.for(:jld)            #=> JSON::LD::Format
  #     RDF::Format.for("etc/foaf.jld")
  #     RDF::Format.for(:file_name      => "etc/foaf.jld")
  #     RDF::Format.for(:file_extension => "jld")
  #     RDF::Format.for(:content_type   => "application/json")
  #
  # @example Obtaining serialization format MIME types
  #     RDF::Format.content_types      #=> {"application/json" => [JSON::LD::Format]}
  #
  # @example Obtaining serialization format file extension mappings
  #     RDF::Format.file_extensions    #=> {:ttl => "application/json"}
  #
  # @see http://www.w3.org/TR/rdf-testcases/#ntriples
  class Format < RDF::Format
    content_type     'application/json',    :extension => :jld
    content_encoding 'utf-8'

    reader { RDF::N3::Reader }
    writer { RDF::N3::Writer }
  end
end
