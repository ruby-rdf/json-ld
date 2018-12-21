$:.unshift(File.join("../../lib", __FILE__))
$:.unshift File.dirname(__FILE__)

require "bundler/setup"
require 'rspec'
require 'rdf'
require 'rdf/isomorphic'
require 'rdf/nquads'
require 'rdf/turtle'
require 'rdf/trig'
require 'rdf/vocab'
require 'rdf/spec'
require 'rdf/spec/matchers'
require_relative 'matchers'
require 'yaml'
begin
  require 'simplecov'
  require 'coveralls' unless ENV['NOCOVERALLS']
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    (Coveralls::SimpleCov::Formatter unless ENV['NOCOVERALLS'])
  ])
  SimpleCov.start do
    add_filter "/spec/"
  end
rescue LoadError
end

require 'json/ld'

JSON_STATE = JSON::State.new(
  indent:       "  ",
  space:        " ",
  space_before: "",
  object_nl:    "\n",
  array_nl:     "\n"
)

require 'webmock'
WebMock.disable_net_connect!

# Create and maintain a cache of downloaded URIs
URI_CACHE = File.expand_path(File.join(File.dirname(__FILE__), "uri-cache"))
Dir.mkdir(URI_CACHE) unless File.directory?(URI_CACHE)
# Cache client requests

::RSpec.configure do |c|
  c.filter_run focus: true
  c.run_all_when_everything_filtered = true
  c.include(RDF::Spec::Matchers)
end

# Heuristically detect the input stream
def detect_format(stream)
  # Got to look into the file to see
  if stream.respond_to?(:rewind) && stream.respond_to?(:read)
    stream.rewind
    string = stream.read(1000)
    stream.rewind
  else
    string = stream.to_s
  end
  case string
  when /<html/i           then RDF::RDFa::Reader
  when /\{\s*\"@\"/i      then JSON::LD::Reader
  else                         RDF::Turtle::Reader
  end
end

LIBRARY_INPUT = JSON.parse(%([
  {
    "@id": "http://example.org/library",
    "@type": "http://example.org/vocab#Library",
    "http://example.org/vocab#contains": {"@id": "http://example.org/library/the-republic"}
  }, {
    "@id": "http://example.org/library/the-republic",
    "@type": "http://example.org/vocab#Book",
    "http://purl.org/dc/elements/1.1/creator": "Plato",
    "http://purl.org/dc/elements/1.1/title": "The Republic",
    "http://example.org/vocab#contains": {
      "@id": "http://example.org/library/the-republic#introduction",
      "@type": "http://example.org/vocab#Chapter",
      "http://purl.org/dc/elements/1.1/description": "An introductory chapter on The Republic.",
      "http://purl.org/dc/elements/1.1/title": "The Introduction"
    }
  }
]))

LIBRARY_EXPANDED = JSON.parse(%([
  {
    "@id": "http://example.org/library",
    "@type": ["http://example.org/vocab#Library"],
    "http://example.org/vocab#contains": [{"@id": "http://example.org/library/the-republic"}]
  }, {
    "@id": "http://example.org/library/the-republic",
    "@type": ["http://example.org/vocab#Book"],
    "http://purl.org/dc/elements/1.1/creator": [{"@value": "Plato"}],
    "http://purl.org/dc/elements/1.1/title": [{"@value": "The Republic"}],
    "http://example.org/vocab#contains": [{
      "@id": "http://example.org/library/the-republic#introduction",
      "@type": ["http://example.org/vocab#Chapter"],
      "http://purl.org/dc/elements/1.1/description": [{"@value": "An introductory chapter on The Republic."}],
      "http://purl.org/dc/elements/1.1/title": [{"@value": "The Introduction"}]
    }]
  }
]))

LIBRARY_COMPACTED_DEFAULT = JSON.parse(%({
  "@context": "http://schema.org",
  "@graph": [
    {
      "id": "http://example.org/library",
      "type": "http://example.org/vocab#Library",
      "http://example.org/vocab#contains": {"id": "http://example.org/library/the-republic"}
    }, {
      "id": "http://example.org/library/the-republic",
      "type": "http://example.org/vocab#Book",
      "http://purl.org/dc/elements/1.1/creator": "Plato",
      "http://purl.org/dc/elements/1.1/title": "The Republic",
      "http://example.org/vocab#contains": {
        "id": "http://example.org/library/the-republic#introduction",
        "type": "http://example.org/vocab#Chapter",
        "http://purl.org/dc/elements/1.1/description": "An introductory chapter on The Republic.",
        "http://purl.org/dc/elements/1.1/title": "The Introduction"
      }
    }
  ]
}))

LIBRARY_COMPACTED = JSON.parse(%({
  "@context": "http://conneg.example.com/context",
  "@graph": [
    {
      "@id": "http://example.org/library",
      "@type": "ex:Library",
      "ex:contains": {
        "@id": "http://example.org/library/the-republic"
      }
    },
    {
      "@id": "http://example.org/library/the-republic",
      "@type": "ex:Book",
      "dc:creator": "Plato",
      "dc:title": "The Republic",
      "ex:contains": {
        "@id": "http://example.org/library/the-republic#introduction",
        "@type": "ex:Chapter",
        "dc:description": "An introductory chapter on The Republic.",
        "dc:title": "The Introduction"
      }
    }
  ]
}))

LIBRARY_FLATTENED_EXPANDED = JSON.parse(%([
  {
    "@id": "http://example.org/library",
    "@type": ["http://example.org/vocab#Library"],
    "http://example.org/vocab#contains": [{"@id": "http://example.org/library/the-republic"}]
  },
  {
    "@id": "http://example.org/library/the-republic",
    "@type": ["http://example.org/vocab#Book"],
    "http://purl.org/dc/elements/1.1/creator": [{"@value": "Plato"}],
    "http://purl.org/dc/elements/1.1/title": [{"@value": "The Republic"}],
    "http://example.org/vocab#contains": [{"@id": "http://example.org/library/the-republic#introduction"}]
  },
  {
    "@id": "http://example.org/library/the-republic#introduction",
    "@type": ["http://example.org/vocab#Chapter"],
    "http://purl.org/dc/elements/1.1/description": [{"@value": "An introductory chapter on The Republic."}],
    "http://purl.org/dc/elements/1.1/title": [{"@value": "The Introduction"}]
  }
]))

LIBRARY_FLATTENED_COMPACTED_DEFAULT = JSON.parse(%({
  "@context": "http://schema.org",
  "@graph": [
    {
      "id": "http://example.org/library",
      "type": "http://example.org/vocab#Library",
      "http://example.org/vocab#contains": {"id": "http://example.org/library/the-republic"}
    },
    {
      "id": "http://example.org/library/the-republic",
      "type": "http://example.org/vocab#Book",
      "http://purl.org/dc/elements/1.1/creator": "Plato",
      "http://purl.org/dc/elements/1.1/title": "The Republic",
      "http://example.org/vocab#contains": {"id": "http://example.org/library/the-republic#introduction"}
    },
    {
      "id": "http://example.org/library/the-republic#introduction",
      "type": "http://example.org/vocab#Chapter",
      "http://purl.org/dc/elements/1.1/description": "An introductory chapter on The Republic.",
      "http://purl.org/dc/elements/1.1/title": "The Introduction"
    }
  ]
}))

LIBRARY_FLATTENED_COMPACTED = JSON.parse(%({
  "@context": "http://conneg.example.com/context",
  "@graph": [
    {
      "@id": "http://example.org/library",
      "@type": "ex:Library",
      "ex:contains": {"@id": "http://example.org/library/the-republic"}
    },
    {
      "@id": "http://example.org/library/the-republic",
      "@type": "ex:Book",
      "dc:creator": "Plato",
      "dc:title": "The Republic",
      "ex:contains": {"@id": "http://example.org/library/the-republic#introduction"}
    },
    {
      "@id": "http://example.org/library/the-republic#introduction",
      "@type": "ex:Chapter",
      "dc:description": "An introductory chapter on The Republic.",
      "dc:title": "The Introduction"
    }
  ]
}))

LIBRARY_FRAMED = JSON.parse(%({
  "@context": {
    "dc": "http://purl.org/dc/elements/1.1/",
    "ex": "http://example.org/vocab#"
  },
  "@graph": [
    {
      "@id": "http://example.org/library",
      "@type": "ex:Library",
      "ex:contains": {
        "@id": "http://example.org/library/the-republic",
        "@type": "ex:Book",
        "dc:creator": "Plato",
        "dc:title": "The Republic",
        "ex:contains": {
          "@id": "http://example.org/library/the-republic#introduction",
          "@type": "ex:Chapter",
          "dc:description": "An introductory chapter on The Republic.",
          "dc:title": "The Introduction"
        }
      }
    }
  ]
}))
