require 'linkeddata'

graph = RDF::Graph.new
graph << [RDF::URI("http://www.museum.com/fish"), 
          RDF.type, 
          RDF::URI("http://www.cidoc-crm.org/cidoc-crm/E55_Type")]

unframed_json = JSON::LD::API::fromRdf(graph)


# Using this frame:
frame = {
  "@context"=> [
    "https://linked.art/ns/context/1/full.jsonld",
    {"crm" => "http://www.cidoc-crm.org/cidoc-crm/"}
  ]
}

# This works
puts JSON::LD::API.frame(unframed_json, frame, base: "http://www.example.com")

# But this doesn't.
begin
  puts JSON::LD::API.frame(unframed_json, frame)
rescue JSON::LD::JsonLdError::InvalidBaseIRI => e
  puts "This doesn't work: #{e}"
end


# But using this frame:
frame = {
  "@context"=> [
    {"crm" => "http://www.cidoc-crm.org/cidoc-crm/"}
  ]
}
# Both of these work
puts JSON::LD::API.frame(unframed_json, frame, base: "http://www.example.com")
puts JSON::LD::API.frame(unframed_json, frame)
