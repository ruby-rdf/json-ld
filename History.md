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