# JSON-LD reader/writer

[JSON-LD][] reader/writer for [RDF.rb][RDF.rb] and fully conforming [JSON-LD API][] processor. Additionally this gem implements [JSON-LD Framing][].

[![Gem Version](https://badge.fury.io/rb/json-ld.svg)](https://rubygems.org/gems/json-ld)
[![Build Status](https://github.com/ruby-rdf/json-ld/actions/workflows/ci.yml/badge.svg)](https://github.com/ruby-rdf/json-ld/actions?query=workflow%3ACI)
[![Coverage Status](https://coveralls.io/repos/ruby-rdf/json-ld/badge.svg?branch=develop)](https://coveralls.io/github/ruby-rdf/json-ld?branch=develop)
[![Gitter chat](https://badges.gitter.im/ruby-rdf.png)](https://gitter.im/gitterHQ/gitter)

## Features

JSON::LD parses and serializes [JSON-LD][] into [RDF][] and implements expansion, compaction and framing API interfaces. It also extracts JSON-LD from HTML.

JSON::LD can now be used to create a _context_ from an RDFS/OWL definition, and optionally include a JSON-LD representation of the ontology itself. This is currently accessed through the `script/gen_context` script.

* If the [jsonlint][] gem is installed, it will be used when validating an input document.
* If available, uses [Nokogiri][] for parsing HTML, falls back to REXML otherwise.
* Provisional support for [JSON-LD-star][JSON-LD-star].

[Implementation Report](https://ruby-rdf.github.io/json-ld/etc/earl.html)

Install with `gem install json-ld`

### JSON-LD Streaming Profile
This gem implements an optimized streaming reader used for generating RDF from large dataset dumps formatted as JSON-LD. Such documents must correspond to the [JSON-LD Streaming Profile](https://w3c.github.io/json-ld-streaming/):

* Keys in JSON objects must be ordered with any of `@context`, and/or `@type` coming before any other keys, in that order. This includes aliases of those keys. It is strongly encouraged that `@id` be present, and come immediately after.
* JSON-LD documents can be signaled or requested in [streaming document form](https://w3c.github.io/json-ld-streaming/#dfn-streaming-document-form). The profile URI identifying the [streaming document form](https://w3c.github.io/json-ld-streaming/#dfn-streaming-document-form) is `http://www.w3.org/ns/json-ld#streaming`.

This gem also implements an optimized streaming writer used for generating JSON-LD from large repositories. Such documents result in the JSON-LD Streaming Profile:

* Each statement written as a separate node in expanded/flattened form.
* `RDF List`s are written as separate nodes using `rdf:first` and `rdf:rest` properties.

The order of triples retrieved from the `RDF::Enumerable` dataset determines the way that JSON-LD node objects are written; for best results, statements should be ordered by _graph name_, _subject_, _predicate_ and _object_.

### MultiJson parser
The [MultiJson](https://rubygems.org/gems/multi_json) gem is used for parsing and serializing JSON; this defaults to the native JSON parser/serializer, but will use a more performant parser if one is available. A specific parser can be specified by adding the `:adapter` option to any API call. Additionally, a custom serialilzer may be specified by passing the `:serializer` option to {JSON::LD::Writer} or methods of {JSON::LD::API}. See [MultiJson](https://rubygems.org/gems/multi_json) for more information.

### JSON-LD-star (RDFStar)

The {JSON::LD::API.expand}, {JSON::LD::API.compact}, {JSON::LD::API.toRdf}, and {JSON::LD::API.fromRdf} API methods, along with the {JSON::LD::Reader} and {JSON::LD::Writer}, include provisional support for [JSON-LD-star][JSON-LD-star].

Internally, an `RDF::Statement` is treated as another resource, along with `RDF::URI` and `RDF::Node`, which allows an `RDF::Statement` to have a `#subject` or `#object` which is also an `RDF::Statement`.

In JSON-LD, with the `rdfstar` option set, the value of `@id`, in addition to an IRI or Blank Node Identifier, can be a JSON-LD node object having exactly one property with an optional `@id`, which may also be an embedded object. (It may also have `@context` and `@index` values).

    {
      "@id": {
        "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
        "@index": "ignored",
        "@id": "bob",
        "foaf:age" 23
      },
      "ex:certainty": 0.9
    }

Additionally, the `@annotation` property (or alias) may be used on a node object or value object to annotate the statement for which the associated node is the object of a triple.

    {
      "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
      "@id": "bob",
      "foaf:age" 23,
      "@annotation": {
        "ex:certainty": 0.9
      }
    }

In the first case, the embedded node is not asserted, and only appears as the subject of a triple. In the second case, the triple is asserted and used as the subject in another statement which annotates it.

**Note: This feature is subject to change or elimination as the standards process progresses.**

#### Serializing a Graph containing embedded statements

    require 'json/ld'
    statement = RDF::Statement(RDF::URI('bob'), RDF::Vocab::FOAF.age, RDF::Literal(23))
    graph = RDF::Graph.new << [statement, RDF::URI("ex:certainty"), RDF::Literal(0.9)]
    graph.dump(:jsonld, validate: false, standard_prefixes: true)
    # => {"@id": {"@id": "bob", "foaf:age" 23}, "ex:certainty": 0.9}

Alternatively, using the {JSON::LD::API.fromRdf} method:

    JSON::LD::API::fromRdf(graph)
    # => {"@id": {"@id": "bob", "foaf:age" 23}, "ex:certainty": 0.9}

#### Reading a Graph containing embedded statements

By default, {JSON::LD::API.toRdf} (and {JSON::LD::Reader}) will reject a document containing a subject resource.

    jsonld = %({
      "@id": {
        "@id": "bob", "foaf:age" 23
      },
      "ex:certainty": 0.9
    })
    graph = RDF::Graph.new << JSON::LD::API.toRdf(input)
    # => JSON::LD::JsonLdError::InvalidIdValue

{JSON::LD::API.toRdf} (and {JSON::LD::Reader}) support a boolean valued `rdfstar` option; only one statement is asserted, although the reified statement is contained within the graph.

    graph = RDF::Graph.new do |graph|
      JSON::LD::Reader.new(jsonld, rdfstar: true) {|reader| graph << reader}
    end
    graph.count #=> 1

## Examples

```ruby
require 'rubygems'
require 'json/ld'
 ```

### Expand a Document

```ruby
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
        "http://xmlns.com/foaf/0.1/name": [{"@value"=>"Manu Sporny"}],
        "http://xmlns.com/foaf/0.1/homepage": [{"@value"=>"https://manu.sporny.org/"}], 
        "http://xmlns.com/foaf/0.1/avatar": [{"@value": "https://twitter.com/account/profile_image/manusporny"}]
    }]
```

### Compact a Document

    input = JSON.parse %([{
        "http://xmlns.com/foaf/0.1/name": ["Manu Sporny"],
        "http://xmlns.com/foaf/0.1/homepage": [{"@id": "https://manu.sporny.org/"}],
        "http://xmlns.com/foaf/0.1/avatar": [{"@id": "https://twitter.com/account/profile_image/manusporny"}]
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
        "avatar": "https://twitter.com/account/profile_image/manusporny",
        "homepage": "https://manu.sporny.org/",
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
        "":       "https://manu.sporny.org/",
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

      <https://manu.sporny.org/#me> a foaf:Person;
         foaf:knows [ a foaf:Person;
           foaf:name "Gregg Kellogg"];
         foaf:name "Manu Sporny" .
    ))
    
    context = JSON.parse %({
      "@context": {
        "":       "https://manu.sporny.org/",
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
          "@id": "https://manu.sporny.org/#me",
          "@type": ["http://xmlns.com/foaf/0.1/Person"],
          "http://xmlns.com/foaf/0.1/knows": [{"@id": "_:g70265766605380"}],
          "http://xmlns.com/foaf/0.1/name": [{"@value": "Manu Sporny"}]
        }
      ]

## Use a custom Document Loader
In some cases, the built-in document loader {JSON::LD::API.documentLoader} is inadequate; for example, when using `http://schema.org` as a remote context, it will be re-loaded every time (however, see [json-ld-preloaded](https://rubygems.org/gems/json-ld-preloaded)).

All entries into the {JSON::LD::API} accept a `:documentLoader` option, which can be used to provide an alternative method to use when loading remote documents. For example:

```ruby
load_document_local = Proc.new do |url, **options, &block|
  if RDF::URI(url, canonicalize: true) == RDF::URI('http://schema.org/')
    remote_document = JSON::LD::API::RemoteDocument.new(url, File.read("etc/schema.org.jsonld"))
    return block_given? ? yield(remote_document) : remote_document
  else
    JSON::LD::API.documentLoader(url, options, &block)
  end
end

```
Then, when performing something like expansion:

```ruby
JSON::LD::API.expand(input, documentLoader: load_document_local)
```

## Preloading contexts
In many cases, for small documents, processing time can be dominated by loading and parsing remote contexts. In particular, a small schema.org example may need to download a large context and turn it into an internal representation, before the actual document can be expanded for processing. Using {JSON::LD::Context.add_preloaded}, an implementation can perform this loading up-front, and make it available to the processor.

```ruby
    ctx = JSON::LD::Context.new().parse('http://schema.org/')
    JSON::LD::Context.add_preloaded('http://schema.org/', ctx)
 ```

On lookup, URIs with an `https` prefix are normalized to `http`.

A context may be serialized to Ruby to speed this process using `Context#to_rb`. When loaded, this generated file will add entries to the {JSON::LD::Context::PRELOADED}.

## RDF Reader and Writer
{JSON::LD} also acts as a normal RDF reader and writer, using the standard RDF.rb reader/writer interfaces:

```ruby
    graph = RDF::Graph.load("etc/doap.jsonld", format: :jsonld)
    graph.dump(:jsonld, standard_prefixes: true)
```

`RDF::GRAPH#dump` can also take a `:context` option to use a separately defined context

As JSON-LD may come from many different sources, included as an embedded script tag within an HTML document, the RDF Reader will strip input before the leading `{` or `[` and after the trailing `}` or `]`.

## Extensions from JSON-LD 1.0
This implementation is being used as a test-bed for features planned for an upcoming JSON-LD 1.1 Community release.

### Scoped Contexts
A term definition can include `@context`, which is applied to values of that object. This is also used when compacting. Taken together, this allows framing to effectively include context definitions more deeply within the framed structure.

    {
      "@context": {
        "ex": "http://example.com/",
        "foo": {
          "@id": "ex:foo",
          "@type": "@vocab"
          "@context": {
            "Bar": "ex:Bar",
            "Baz": "ex:Baz"
          }
        }
      },
      "foo": "Bar"
    }

### @id and @type maps
The value of `@container` in a term definition can include `@id` or `@type`, in addition to `@set`, `@list`, `@language`, and `@index`. This allows value indexing based on either the `@id` or `@type` of associated objects.

    {
      "@context": {
        "@vocab": "http://example/",
        "idmap": {"@container": "@id"}
      },
      "idmap": {
        "http://example.org/foo": {"label": "Object with @id <foo>"},
        "_:bar": {"label": "Object with @id _:bar"}
      }
    }

### @graph containers and maps
A term can have `@container` set to include `@graph` optionally including `@id` or `@index` and `@set`. In the first form, with `@container` set to `@graph`, the value of a property is treated as a _simple graph object_, meaning that values treated as if they were contained in an object with `@graph`, creating _named graph_ with an anonymous name.

    {
      "@context": {
        "@vocab": "http://example.org/",
        "input": {"@container": "@graph"}
      },
      "input": {
        "value": "x"
      }
    }

which expands to the following:

    [{
      "http://example.org/input": [{
        "@graph": [{
          "http://example.org/value": [{"@value": "x"}]
        }]
      }]
    }]

Compaction reverses this process, optionally ensuring that a single value is contained within an array of `@container` also includes `@set`:

    {
      "@context": {
        "@vocab": "http://example.org/",
        "input": {"@container": ["@graph", "@set"]}
      }
    }

A graph map uses the map form already existing for `@index`, `@language`, `@type`, and `@id` where the index is either an index value or an id.

    {
      "@context": {
        "@vocab": "http://example.org/",
        "input": {"@container": ["@graph", "@index"]}
      },
      "input": {
        "g1": {"value": "x"}
      }
    }

treats "g1" as an index, and expands to the following:

    [{
      "http://example.org/input": [{
        "@index": "g1",
        "@graph": [{
          "http://example.org/value": [{"@value": "x"}]
        }]
      }]
    }])

This can also include `@set` to ensure that, when compacting, a single value of an index will be in array form.

The _id_ version is similar:

    {
      "@context": {
        "@vocab": "http://example.org/",
        "input": {"@container": ["@graph", "@id"]}
      },
      "input": {
        "http://example.com/g1": {"value": "x"}
      }
    }

which expands to:

    [{
      "http://example.org/input": [{
        "@id": "http://example.com/g1",
        "@graph": [{
          "http://example.org/value": [{"@value": "x"}]
        }]
      }]
    }])

### Transparent Nesting
Many JSON APIs separate properties from their entities using an intermediate object. For example, a set of possible labels may be grouped under a common property:

    {
      "@context": {
        "skos": "http://www.w3.org/2004/02/skos/core#",
        "labels": "@nest",
        "main_label": {"@id": "skos:prefLabel"},
        "other_label": {"@id": "skos:altLabel"},
        "homepage": {"@id":"http://schema.org/description", "@type":"@id"}
      },
      "@id":"http://example.org/myresource",
      "homepage": "http://example.org",
      "labels": {
         "main_label": "This is the main label for my resource",
         "other_label": "This is the other label"
      }
    }
 
 In this case, the `labels` property is semantically meaningless. Defining it as equivalent to `@nest` causes it to be ignored when expanding, making it equivalent to the following:

    {
      "@context": {
        "skos": "http://www.w3.org/2004/02/skos/core#",
        "labels": "@nest",
        "main_label": {"@id": "skos:prefLabel"},
        "other_label": {"@id": "skos:altLabel"},
        "homepage": {"@id":"http://schema.org/description", "@type":"@id"}
      },
      "@id":"http://example.org/myresource",
      "homepage": "http://example.org",
      "main_label": "This is the main label for my resource",
      "other_label": "This is the other label"
    }
 
 Similarly, properties may be marked with "@nest": "nest-term", to cause them to be nested. Note that the `@nest` keyword can also be aliased in the context.

     {
       "@context": {
         "skos": "http://www.w3.org/2004/02/skos/core#",
         "labels": "@nest",
         "main_label": {"@id": "skos:prefLabel", "@nest": "labels"},
         "other_label": {"@id": "skos:altLabel", "@nest": "labels"},
         "homepage": {"@id":"http://schema.org/description", "@type":"@id"}
       },
       "@id":"http://example.org/myresource",
       "homepage": "http://example.org",
       "labels": {
          "main_label": "This is the main label for my resource",
          "other_label": "This is the other label"
       }
     }

In this way, nesting survives round-tripping through expansion, and framed output can include nested properties.

## Sinatra/Rack support
JSON-LD 1.1 describes support for the _profile_ parameter to a media type in an HTTP ACCEPT header. This allows an HTTP request to specify the format (expanded/compacted/flattened/framed) along with a reference to a context or frame to use to format the returned document.

An HTTP header may be constructed as follows:

    GET /ordinary-json-document.json HTTP/1.1
    Host: example.com
    Accept: application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://conneg.example.com/context", application/ld+json

This tells a server that the top priority is to return JSON-LD compacted using a context at `http://conneg.example.com/context`, and if not available, to just return any form of JSON-LD.

The {JSON::LD::ContentNegotiation} class provides a [Rack][Rack] `call` method, and [Sinatra][Sinatra] `registered` class method to allow content-negotiation using such profile parameters. For example:

    #!/usr/bin/env rackup
    require 'sinatra/base'
    require 'json/ld'
    
    module My
      class Application < Sinatra::Base
        register JSON::LD::ContentNegotiation
    
        get '/hello' do
          [{
            "http://example.org/input": [{
              "@id": "http://example.com/g1",
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }]
            }]
          }])
        end
      end
    end
    
    run My::Application

The {JSON::LD::ContentNegotiation#call} method looks for a result which includes an object, with an acceptable `Accept` header and formats the result as JSON-LD, considering the profile parameters. This can be tested using something like the following:

    $ rackup config.ru
    
    $ curl -iH 'Accept: application/ld+json;profile="http://www.w3.org/ns/json-ld#compacted http://conneg.example.com/context"' http://localhost:9292/hello

See [Rack::LinkedData][] to do the same thing with an RDF Graph or Dataset as the source, rather than Ruby objects.

## Documentation
Full documentation available on [RubyDoc](https://ruby-rdf.github.io/json-ld/file/README.md)

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
* [Ruby](https://ruby-lang.org/) (>= 3.0)
* [RDF.rb](https://rubygems.org/gems/rdf) (~> 3.3)
* [JSON](https://rubygems.org/gems/json) (>= 2.6)

## Installation
The recommended installation method is via [RubyGems](https://rubygems.org/).
To install the latest official release of the `JSON-LD` gem, do:

    % [sudo] gem install json-ld

## Download
To get a local working copy of the development repository, do:

    % git clone git://github.com/ruby-rdf/json-ld.git

## Change Log

See [Release Notes on GitHub](https://github.com/ruby-rdf/json-ld/releases)

## Mailing List
* <https://lists.w3.org/Archives/Public/public-rdf-ruby/>

## Author
* [Gregg Kellogg](https://github.com/gkellogg) - <https://greggkellogg.net/>

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
  explicit [public domain dedication][PDD] on record from you,
  which you will be asked to agree to on the first commit to a repo within the organization.
  Note that the agreement applies to all repos in the [Ruby RDF](https://github.com/ruby-rdf/) organization.

## License

This is free and unencumbered public domain software. For more information,
see <https://unlicense.org/> or the accompanying {file:UNLICENSE} file.

[Ruby]:             https://ruby-lang.org/
[RDF]:              https://www.w3.org/RDF/
[YARD]:             https://yardoc.org/
[YARD-GS]:          https://rubydoc.info/docs/yard/file/docs/GettingStarted.md
[PDD]:              https://unlicense.org/#unlicensing-contributions
[RDF.rb]:           https://rubygems.org/gems/rdf
[JSON-LD-star]:             https://json-ld.github.io/json-ld-star/
[Rack::LinkedData]: https://rubygems.org/gems/rack-linkeddata
[Backports]:        https://rubygems.org/gems/backports
[JSON-LD]:          https://www.w3.org/TR/json-ld11/ "JSON-LD 1.1"
[JSON-LD API]:      https://www.w3.org/TR/json-ld11-api/ "JSON-LD 1.1 Processing Algorithms and API"
[JSON-LD Framing]:  https://www.w3.org/TR/json-ld11-framing/ "JSON-LD 1.1 Framing"
[Promises]:         https://dom.spec.whatwg.org/#promises
[jsonlint]:         https://rubygems.org/gems/jsonlint
[Sinatra]:          https://www.sinatrarb.com/
[Rack]:             https://rack.github.com/
