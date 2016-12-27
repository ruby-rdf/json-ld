require 'json/ld'
require 'rdf/ntriples'

def load_file(file)
  RDF::Graph.new.tap do |g|
    RDF::Reader.for(:content_type => "text/plain").open(file) do |reader|
      g << reader.statements
    end
  end
end

input = JSON.parse(load_file(File.expand_path('../input.nt', __FILE__)).dump(:jsonld))

build_framing = {
  "@context" => {
    "uuid" => "http://www.domain.com/profile/client/resource/",
    "pmcore" => "http://www.domain.com/ontology/pmcore/1.0#",
    "pmaudiovisual" => "http://www.domain.com/ontology/pmaudiovisual/1.0#",
    "pmadditionalsubjects" => "http://www.domain.com/ontology/pmadditionalsubjects/",
    "pmmodel" => "http://www.domain.com/ontology/pmmodel/1.0#",
    "kb" => "http://www.domain.com/profile/client/kb/",
    "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
    "dc" => "http://purl.org/dc/elements/1.1/",
    "client" => "http://www.domain.com/ontology/client/1.0#",
    "freebase" => "http://rdf.freebase.com/ns/",
    "cents" => "http://www.domain.com/profile/1000cents/resource/",
    "owl" => "http://www.w3.org/2002/07/owl#",
    "skos" => "http://www.w3.org/2008/05/skos#"
  },
  "@id" => "kb:148F9D55-482A-4A96-B06F-16E05D44AA15",
  "@embed" => "@last"
}

puts JSON::LD::API.frame(input, build_framing).to_json(JSON::LD::JSON_STATE)
