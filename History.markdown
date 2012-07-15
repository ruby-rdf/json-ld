=== 0.1.4.1
* Include rdf-xsd for some specs.
* Refactor #expand_value to deal with previous matching on RDF::Literal::Integer for sub-types.
 
=== 0.1.4
* Added bin/jsonld for command-line manipulation of JSON-LD files and to perform RDF transformations.

=== 0.1.3
* Progress release syncing with the spec. Most expansion and compaction tests pass. RDF is okay, framing has many issues.

=== 0.1.1
* Changed @literal to @value.
* Change expanded double format to %1.6e
* Only recognize application/ld+json and :jsonld.

=== 0.1.0
* New @context processing rules.
* @iri and @subject changed to @id.
* @datatype changed to @type.
* @coerce keys can be CURIEs or IRIs (not spec'd).
* @language in @context.
* Implemented JSON::LD::API for .compact and .expand.
* Support relative IRI expansion based on document location.
* Make sure that keyword aliases are fully considered on both input and output and used when compacting.

=== 0.0.8
* RDF.rb 0.3.4 compatibility.
* Format detection.
* Use new @list syntax for parsing ordered collections.
* Separate normalize from canonicalize


=== 0.0.7
* Change MIME Type and extension from application/json, .json to application/ld+json, .jsonld.
  * Also added application/x-ld+json
* Process a remote @context
* Updated to current state of spec, including support for aliased keywords
* Update Writer to output consistent with current spec.

=== 0.0.6
* Another order problem (in literals)

=== 0.0.5
* Fix @literal, @language, @datatype, and @iri serialization
* Use InsertOrderPreservingHash for Ruby 1.8

=== 0.0.4
* Fixed ruby 1.8 hash-order problem when parsing @context.
* Add .jsonld file extention and format
* JSON-LD Writer
* Use test suite from json.org
* Use '@type' instead of 'a' and '@subject' instead of '@'

=== 0.0.3
* Downgrade RDF.rb requirement from 0.4.0 to 0.3.3.

=== 0.0.2
* Functional Reader with reasonable test coverage.

=== 0.0.1
* First release of project scaffold.