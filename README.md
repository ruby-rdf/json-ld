# JSON-LD reader/writer

[JSON-LD][] reader/writer for [RDF.rb][RDF.rb] and fully conforming [JSON-LD API][] processor. Additionally this gem implements [JSON-LD Framing][].

[![Gem Version](https://badge.fury.io/rb/json-ld.png)](http://badge.fury.io/rb/json-ld)
[![Build Status](https://secure.travis-ci.org/ruby-rdf/json-ld.png?branch=master)](http://travis-ci.org/ruby-rdf/json-ld)
[![Coverage Status](https://coveralls.io/repos/ruby-rdf/json-ld/badge.svg)](https://coveralls.io/r/ruby-rdf/json-ld)

## Features

JSON::LD parses and serializes [JSON-LD][] into [RDF][] and implements expansion, compaction and framing API interfaces.

JSON::LD can now be used to create a _context_ from an RDFS/OWL definition, and optionally include a JSON-LD representation of the ontology itself. This is currently accessed through the `script/gen_context` script.

If the [jsonlint][] gem is installed, it will be used when validating an input document.

Install with `gem install json-ld`

### JSON-LD Streaming Profile
This gem implements an optimized streaming writer used for generating JSON-LD from large repositories. Such documents result in the JSON-LD Streaming Profile:

* Each statement written as a separate node in expanded/flattened form.
* RDF Lists are written as separate nodes using `rdf:first` and `rdf:rest` properties.

## Examples

    require 'rubygems'
    require 'json/ld'

### Expand a Document

    input = JSON.parse %({
      "@context": {
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": "http://xmlns.com/foaf/0.1/homepage",
        "avatar": "http://xmlns.com/foaf/0.1/avatar"
      },
      "name": "Manu Sporny",
      "homepage": "http://manu.sporny.org/",
      "avatar": "http://twitter.com/account/profile_image/manusporny"
    })
    JSON::LD::API.expand(input) =>
    
    [{
        "http://xmlns.com/foaf/0.1/name": ["Manu Sporny"],
        "http://xmlns.com/foaf/0.1/homepage": ["http://manu.sporny.org/"],
        "http://xmlns.com/foaf/0.1/avatar": ["http://twitter.com/account/profile_image/manusporny"]
    }]

### Compact a Document

    input = JSON.parse %([{
        "http://xmlns.com/foaf/0.1/name": ["Manu Sporny"],
        "http://xmlns.com/foaf/0.1/homepage": [{"@id": "http://manu.sporny.org/"}],
        "http://xmlns.com/foaf/0.1/avatar": [{"@id": "http://twitter.com/account/profile_image/manusporny"}]
    }])
    
    context = JSON.parse(%({
      "@context": {
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
        "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
      }
    }))['@context']
    
    JSON::LD::API.compact(input, context) =>
    {
        "@context": {
          "name": "http://xmlns.com/foaf/0.1/name",
          "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
          "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
        },
        "avatar": "http://twitter.com/account/profile_image/manusporny",
        "homepage": "http://manu.sporny.org/",
        "name": "Manu Sporny"
    }

### Frame a Document

    input = JSON.parse %({
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
    })
    
    frame = JSON.parse %({
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
    })

    JSON::LD::API.frame(input, frame) =>
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

    input = JSON.parse %({
      "@context": {
        "":       "http://manu.sporny.org/",
        "foaf":   "http://xmlns.com/foaf/0.1/"
      },
      "@id":       "http://example.org/people#joebob",
      "@type":          "foaf:Person",
      "foaf:name":      "Joe Bob",
      "foaf:nick":      { "@list": [ "joe", "bob", "jaybe" ] }
    })
    
    graph = RDF::Graph.new << JSON::LD::API.toRdf(input)

    require 'rdf/turtle'
    graph.dump(:ttl, prefixes: {foaf: "http://xmlns.com/foaf/0.1/"})
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .

    <http://example.org/people#joebob> a foaf:Person;
       foaf:name "Joe Bob";
       foaf:nick ("joe" "bob" "jaybe") .

### Turn RDF into JSON-LD

    require 'rdf/turtle'
    input = RDF::Graph.new << RDF::Turtle::Reader.new(%(
      @prefix foaf: <http://xmlns.com/foaf/0.1/> .

      <http://manu.sporny.org/#me> a foaf:Person;
         foaf:knows [ a foaf:Person;
           foaf:name "Gregg Kellogg"];
         foaf:name "Manu Sporny" .
    ))
    
    context = JSON.parse %({
      "@context": {
        "":       "http://manu.sporny.org/",
        "foaf":   "http://xmlns.com/foaf/0.1/"
      }
    })

    compacted = nil
    JSON::LD::API::fromRdf(input) do |expanded|
      compacted = JSON::LD::API.compact(expanded, context['@context'])
    end
    compacted =>
      [
        {
          "@id": "_:g70265766605380",
          "@type": ["http://xmlns.com/foaf/0.1/Person"],
          "http://xmlns.com/foaf/0.1/name": [{"@value": "Gregg Kellogg"}]
        },
        {
          "@id": "http://manu.sporny.org/#me",
          "@type": ["http://xmlns.com/foaf/0.1/Person"],
          "http://xmlns.com/foaf/0.1/knows": [{"@id": "_:g70265766605380"}],
          "http://xmlns.com/foaf/0.1/name": [{"@value": "Manu Sporny"}]
        }
      ]

## RDF Reader and Writer
{JSON::LD} also acts as a normal RDF reader and writer, using the standard RDF.rb reader/writer interfaces:

    graph = RDF::Graph.load("etc/doap.jsonld", format: :jsonld)
    graph.dump(:jsonld, standard_prefixes: true)

`RDF::GRAPH#dump` can also take a `:context` option to use a separately defined context

As JSON-LD may come from many different sources, included as an embedded script tag within an HTML document, the RDF Reader will strip input before the leading `{` or `[` and after the trailing `}` or `]`.

## Documentation
Full documentation available on [RubyDoc](http://rubydoc.info/gems/json-ld/file/README.md)

## Differences from [JSON-LD API][]
The specified JSON-LD API is based on a WebIDL definition implementing [Promises][] intended for use within a browser.
This version implements a more Ruby-like variation of this API without the use
of promises or callback arguments, preferring Ruby blocks. All API methods
execute synchronously, so that the return from a method can typically be used as well as a block.

Note, the API method signatures differed in versions before 1.0, in that they also had a callback parameter. And 1.0.6 has some other minor method signature differences than previous versions. This should be the only exception to the use of semantic versioning.

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
* Don't touch the `json-ld.gemspec`, `VERSION` or `AUTHORS` files. If you need to
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
[JSON-LD]:          http://www.w3.org/TR/json-ld/ "JSON-LD 1.0"
[JSON-LD API]:      http://www.w3.org/TR/json-ld-api/ "JSON-LD 1.0 Processing Algorithms and API"
[JSON-LD Framing]:  http://json-ld.org/spec/latest/json-ld-framing/ "JSON-LD Framing 1.0"
[Promises]:         http://dom.spec.whatwg.org/#promises
[jsonlint]:         https://rubygems.org/gems/jsonlint
