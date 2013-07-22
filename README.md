# JSON-LD reader/writer

[JSON-LD][] reader/writer for [RDF.rb][RDF.rb] and fully conforming [JSON-LD][] processor.

[![Gem Version](https://badge.fury.io/rb/json-ld.png)](http://badge.fury.io/rb/json-ld)
[![Build Status](https://secure.travis-ci.org/ruby-rdf/json-ld.png?branch=master)](http://travis-ci.org/ruby-rdf/json-ld)

## Features

JSON::LD parses and serializes [JSON-LD][] into [RDF][] and implements expansion, compaction and framing API interfaces.

Install with `gem install json-ld`

## Examples

    require 'rubygems'
    require 'json/ld'

### Expand a Document

    input = {
      "@context": {
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": "http://xmlns.com/foaf/0.1/homepage",
        "avatar": "http://xmlns.com/foaf/0.1/avatar"
      },
      "name": "Manu Sporny",
      "homepage": "http://manu.sporny.org/",
      "avatar": "http://twitter.com/account/profile_image/manusporny"
    }
    JSON::LD::API.expand(input) =>
    
    [{
        "http://xmlns.com/foaf/0.1/name": ["Manu Sporny"],
        "http://xmlns.com/foaf/0.1/homepage": ["http://manu.sporny.org/"],
        "http://xmlns.com/foaf/0.1/avatar": ["http://twitter.com/account/profile_image/manusporny"]
    }]

### Compact a Document

    input = [{
        "http://xmlns.com/foaf/0.1/name": ["Manu Sporny"],
        "http://xmlns.com/foaf/0.1/homepage": ["http://manu.sporny.org/"],
        "http://xmlns.com/foaf/0.1/avatar": ["http://twitter.com/account/profile_image/manusporny"]
    }]
    
    context = {
      "@context": {
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": "http://xmlns.com/foaf/0.1/homepage",
        "avatar": "http://xmlns.com/foaf/0.1/avatar"
      }
    }
    
    JSON::LD::API.compact(input, context) =>
    {
        "@context": {
            "avatar": "http://xmlns.com/foaf/0.1/avatar",
            "homepage": "http://xmlns.com/foaf/0.1/homepage",
            "name": "http://xmlns.com/foaf/0.1/name"
        },
        "avatar": "http://twitter.com/account/profile_image/manusporny",
        "homepage": "http://manu.sporny.org/",
        "name": "Manu Sporny"
    }

### Frame a Document

    input = {
      "@context": {
        "Book":         "http://example.org/vocab#Book",
        "Chapter":      "http://example.org/vocab#Chapter",
        "contains":     {"@id": "http://example.org/vocab#contains", "@type": "@id"},
        "creator":      "http://purl.org/dc/terms/creator",
        "description":  "http://purl.org/dc/terms/description",
        "Library":      "http://example.org/vocab#Library",
        "title":        "http://purl.org/dc/terms/title"
      },
      "@graph":
      [{
        "@id": "http://example.com/library",
        "@type": "Library",
        "contains": "http://example.org/library/the-republic"
      },
      {
        "@id": "http://example.org/library/the-republic",
        "@type": "Book",
        "creator": "Plato",
        "title": "The Republic",
        "contains": "http://example.org/library/the-republic#introduction"
      },
      {
        "@id": "http://example.org/library/the-republic#introduction",
        "@type": "Chapter",
        "description": "An introductory chapter on The Republic.",
        "title": "The Introduction"
      }]
    }
    
    frame = {
      "@context": {
        "Book":         "http://example.org/vocab#Book",
        "Chapter":      "http://example.org/vocab#Chapter",
        "contains":     "http://example.org/vocab#contains",
        "creator":      "http://purl.org/dc/terms/creator",
        "description":  "http://purl.org/dc/terms/description",
        "Library":      "http://example.org/vocab#Library",
        "title":        "http://purl.org/dc/terms/title"
      },
      "@type": "Library",
      "contains": {
        "@type": "Book",
        "contains": {
          "@type": "Chapter"
        }
      }
    }
    JSON::LD.frame(input, frame) =>
    {
      "@context": {
        "Book": "http://example.org/vocab#Book",
        "Chapter": "http://example.org/vocab#Chapter",
        "contains": "http://example.org/vocab#contains",
        "creator": "http://purl.org/dc/terms/creator",
        "description": "http://purl.org/dc/terms/description",
        "Library": "http://example.org/vocab#Library",
        "title": "http://purl.org/dc/terms/title"
      },
      "@graph": [
        {
          "@id": "http://example.com/library",
          "@type": "Library",
          "contains": {
            "@id": "http://example.org/library/the-republic",
            "@type": "Book",
            "contains": {
              "@id": "http://example.org/library/the-republic#introduction",
              "@type": "Chapter",
              "description": "An introductory chapter on The Republic.",
              "title": "The Introduction"
            },
            "creator": "Plato",
            "title": "The Republic"
          }
        }
      ]
    }

### Turn JSON-LD into RDF (Turtle)

    input = {
      "@context": {
        "":       "http://manu.sporny.org/",
        "foaf":   "http://xmlns.com/foaf/0.1/"
      },
      "@id":       "http://example.org/people#joebob",
      "@type":          "foaf:Person",
      "foaf:name":      "Joe Bob",
      "foaf:nick":      { "@list": [ "joe", "bob", "jaybe" ] }
    }
    
    JSON::LD::API.toRDF(input) =>
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .

    <http://example.org/people#joebob> a foaf:Person;
       foaf:name "Joe Bob";
       foaf:nick ("joe" "bob" "jaybe") .

### Turn RDF into JSON-LD

    input =
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .

    <http://manu.sporny.org/#me> a foaf:Person;
       foaf:knows [ a foaf:Person;
         foaf:name "Gregg Kellogg"];
       foaf:name "Manu Sporny" .
    
    context =
    {
      "@context": {
        "":       "http://manu.sporny.org/",
        "foaf":   "http://xmlns.com/foaf/0.1/"
      }
    }

    JSON::LD::API::fromRDF(input, context) =>
    {
      "@context": {
        "":       "http://manu.sporny.org/",
        "foaf":   "http://xmlns.com/foaf/0.1/"
      },
      "@id":       ":#me",
      "@type":          "foaf:Person",
      "foaf:name":      "Manu Sporny",
      "foaf:knows": {
        "@type":          "foaf:Person",
        "foaf:name":      "Gregg Kellogg"
      }
    }

## RDF Reader and Writer
{JSON::LD} also acts as a normal RDF reader and writer, using the standard RDF.rb reader/writer interfaces:

    graph = RDF::Graph.load("etc/doap.jsonld", :format => :jsonld)
    graph.dump(:jsonld, :standard_prefixes => true)

## Documentation
Full documentation available on [RubyDoc](http://rubydoc.info/gems/json-ld/file/README.md)

## Differences from [JSON-LD API][]
The specified JSON-LD API is based on a WebIDL definition intended for use within the browser.
This version implements a more Ruby-like variation of this API without the use
of futures and callback arguments, preferring Ruby blocks. All API methods
execute synchronously, so that the return from a method can be used as well as a block.

Note, the API method signatures differed in versions before 1.0, in that they also had
a callback parameter.

### Principal Classes
* {JSON::LD}
  * {JSON::LD::API}
  * {JSON::LD::Compact}
  * {JSON::LD::Context}
  * {JSON::LD::Format}
  * {JSON::LD::Frame}
  * {JSON::LD::FromRDF}
  * {JSON::LD::Reader}
  * {JSON::LD::ToRDF}
  * {JSON::LD::Writer}

## Dependencies
* [Ruby](http://ruby-lang.org/) (>= 1.9.2)
* [RDF.rb](http://rubygems.org/gems/rdf) (>= 1.0)
* [JSON](https://rubygems.org/gems/json) (>= 1.5)

## Installation
The recommended installation method is via [RubyGems](http://rubygems.org/).
To install the latest official release of the `JSON-LD` gem, do:

    % [sudo] gem install json-ld

## Download
To get a local working copy of the development repository, do:

    % git clone git://github.com/ruby-rdf/json-ld.git

## Mailing List
* <http://lists.w3.org/Archives/Public/public-rdf-ruby/>

## Author
* [Gregg Kellogg](http://github.com/gkellogg) - <http://kellogg-assoc.com/>

## Contributing
* Do your best to adhere to the existing coding conventions and idioms.
* Don't use hard tabs, and don't leave trailing whitespace on any line.
* Do document every method you add using [YARD][] annotations. Read the
  [tutorial][YARD-GS] or just look at the existing code for examples.
* Don't touch the `.gemspec`, `VERSION` or `AUTHORS` files. If you need to
  change them, do so on your private branch only.
* Do feel free to add yourself to the `CREDITS` file and the corresponding
  list in the the `README`. Alphabetical order applies.
* Do note that in order for us to merge any non-trivial changes (as a rule
  of thumb, additions larger than about 15 lines of code), we need an
  explicit [public domain dedication][PDD] on record from you.

License
-------

This is free and unencumbered public domain software. For more information,
see <http://unlicense.org/> or the accompanying {file:UNLICENSE} file.

[Ruby]:             http://ruby-lang.org/
[RDF]:              http://www.w3.org/RDF/
[YARD]:             http://yardoc.org/
[YARD-GS]:          http://rubydoc.info/docs/yard/file/docs/GettingStarted.md
[PDD]:              http://lists.w3.org/Archives/Public/public-rdf-ruby/2010May/0013.html
[RDF.rb]:           http://rubygems.org/gems/rdf
[Backports]:        http://rubygems.org/gems/backports
[JSON-LD]:          http://json-ld.org/spec/latest/
[JSON-LD API]:      http://json-ld.org/spec/latest/json-ld-api/
