#!/usr/bin/env ruby
require 'json/ld'

context = JSON.parse %({
  "@vocab": "http://schema.org/" , 
  "dc": "http://purl.org/dc/elements/1.1/",
  "doag": "http://academy.dior.com/doag#",
  "dior": "http://academy.dior.com/terms#",
  "name": {
    "@container": "@language"
  }
})

puts JSON::LD::API.compact("http://semio.dydra.com/arnaudlevy/dior-academy/seasons.jsonld?auth_token=rcelIAhAcmnYXv2A2rZ7", context).to_json(JSON::LD::JSON_STATE)
