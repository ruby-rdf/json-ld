# JSON-LD reader/writer

[JSON-LD][] reader/writer for [RDF.rb][RDF.rb] .

## Features

JSON::LD parses and serializes [JSON-LD][] into statements or statements.

Install with `gem install json-ld`

## Examples

    require 'rubygems'
    require 'json/ld'

## Documentation
Full documentation available on [RubyDoc](http://rubydoc.info/gems/json-ld/0.0.4/file/README)

### Principle Classes
* {JSON::LD}
  * {JSON::LD::Format}
  * {JSON::LD::Reader}
  * {JSON::LD::Writer}

## Dependencies
* [Ruby](http://ruby-lang.org/) (>= 1.8.7) or (>= 1.8.1 with [Backports][])
* [RDF.rb](http://rubygems.org/gems/rdf) (>= 0.3.4)
* [JSON](https://rubygems.org/gems/json) (>= 1.5.1)

## Installation
The recommended installation method is via [RubyGems](http://rubygems.org/).
To install the latest official release of the `JSON-LD` gem, do:

    % [sudo] gem install json-ld

## Download
To get a local working copy of the development repository, do:

    % git clone git://github.com/gkellogg/json-ld.git

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
[RDF.rb]:           http://rdf.rubyforge.org/
[Backports]:        http://rubygems.org/gems/backports
[JSON-LD]:          http://json-ld.org/spec/ED/20110507/