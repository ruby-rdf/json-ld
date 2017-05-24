require 'pp'
require 'linkeddata'

input = JSON.parse %({
  "@context": {
    "schema": "http://schema.org/",
    "name": "schema:name",
    "url": {"@id": "schema:url", "@type": "schema:URL"}
  },
  "name": "Jane Doe"
})

frame = JSON.parse %({
  "@context": {
    "schema": "http://schema.org/",
    "name": "schema:name",
    "url": { "@id": "schema:url", "@type": "schema:URL"}
  },
  "name": {},
  "url": {"@default": {"@value": "http://example.com", "@type": "schema:URL"}}
})

pp JSON::LD::API.frame(input, frame, logger: Logger.new(STDERR))