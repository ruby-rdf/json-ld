require 'pp'
require 'linkeddata'

context = JSON.parse %({
  "@context": {
    "id": "@id",
    "rdfs": {"@id": "http://.../"},
    "seeAlso": {"@id": "rdfs:seeAlso", "@container": "@set"}
  }
})

input = JSON.parse %({
  "@context": {
    "id": "@id",
    "rdfs": {"@id": "http://.../"},
    "seeAlso": {"@id": "rdfs:seeAlso", "@container": "@set"}
  },
  "seeAlso": [
    {
      "id": "http://example.org/reference1"
    },
    "http://example.org/reference2",
    {"id": "http://example.org/reference3", "format": "text/html"}
  ]
})

pp JSON::LD::API.compact(input, context['@context'])