#!/usr/bin/env ruby -rubygems
# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.version               = File.read('VERSION').chomp
  gem.date                  = File.mtime('VERSION').strftime('%Y-%m-%d')

  gem.name                  = "json-ld"
  gem.homepage              = "http://github.com/ruby-rdf/json-ld"
  gem.license               = 'Unlicense'
  gem.summary               = "JSON-LD reader/writer for Ruby."
  gem.description           = "JSON::LD parses and serializes JSON-LD into RDF and implements expansion, compaction and framing API interfaces."
  gem.rubyforge_project     = 'json-ld'

  gem.authors               = ['Gregg Kellogg']
  gem.email                 = 'public-linked-json@w3.org'

  gem.platform              = Gem::Platform::RUBY
  gem.files                 = %w(AUTHORS README.md UNLICENSE VERSION) + Dir.glob('lib/**/*.rb')
  gem.bindir               = %q(bin)
  gem.executables          = %w(jsonld)
  gem.default_executable   = gem.executables.first
  gem.require_paths         = %w(lib)
  gem.extensions            = %w()
  gem.test_files            = Dir.glob('spec/**/*.rb') + Dir.glob('spec/test-files/*')
  gem.has_rdoc              = false

  gem.required_ruby_version = '>= 2.2.2'
  gem.requirements          = []
  gem.add_runtime_dependency     'rdf',             '~> 2.2'
  gem.add_runtime_dependency     'multi_json',      '~> 1.12'
  gem.add_development_dependency 'linkeddata',      '~> 2.2'
  gem.add_development_dependency 'jsonlint',        '~> 0.2'  unless RUBY_ENGINE == "jruby"
  gem.add_development_dependency 'oj',              '~> 2.17' unless RUBY_ENGINE == "jruby"
  gem.add_development_dependency 'yajl-ruby',       '~> 1.2'  unless RUBY_ENGINE == "jruby"
  gem.add_development_dependency 'rdf-isomorphic',  '~> 2.0'
  gem.add_development_dependency 'rdf-spec',        '~> 2.2'
  gem.add_development_dependency 'rdf-trig',        '~> 2.0'
  gem.add_development_dependency 'rdf-turtle',      '~> 2.0'
  gem.add_development_dependency 'rdf-vocab',       '~> 2.0'
  gem.add_development_dependency 'rdf-xsd',         '~> 2.0'
  gem.add_development_dependency 'rspec',           '~> 3.5'
  gem.add_development_dependency 'rspec-its',       '~> 1.2'
  gem.add_development_dependency 'yard' ,           '~> 0.8'

  gem.post_install_message  = nil
end
