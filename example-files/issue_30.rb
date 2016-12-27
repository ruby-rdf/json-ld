#! /usr/bin/env ruby

require 'linkeddata'

unframed_json = JSON.parse '[
  {
    "@id": "http://vocab.getty.edu/ulan/500115403",
    "http://xmlns.com/foaf/0.1/focus": [
      {
        "@id": "http://vocab.getty.edu/ulan/500115403-agent"
      }
    ],
    "http://www.w3.org/2004/02/skos/core#prefLabel": [
      {
        "@value": "Couture, Thomas"
      }
    ],
    "http://www.w3.org/2004/02/skos/core#inScheme": [
      {
        "@id": "http://vocab.getty.edu/ulan/"
      }
    ],
    "http://schema.org/url": [
      {
        "@id": "http://www.getty.edu/vow/ULANFullDisplay?find=&role=&nation=&subjectid=500115403"
      }
    ]
  }
]'

frame = JSON.parse '{
  "@explicit": true,
  "@context": {
    "skos": "http://www.w3.org/2004/02/skos/core#",
    "foaf": "http://xmlns.com/foaf/0.1/",
    "schema": "http://schema.org/",
    "label": "skos:prefLabel",
    "id": "@id",
    "source": {
      "@id": "skos:inScheme",
      "@type": "@id"
    },
    "agent": {
      "@id": "foaf:focus",
      "@type": "@id"
    },
    "website": {
      "@id": "schema:url",
      "@type": "@id"
    }
  },
  "@requireAll": false,
  "@explicit": false,
  "label": {},
  "id": {},
  "source": {},
  "agent": {},
  "website": {}
}'

puts JSON::LD::API.frame(unframed_json, frame, logger: STDERR).to_json(JSON::LD::JSON_STATE)
