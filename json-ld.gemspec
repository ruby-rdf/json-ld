#!/usr/bin/env ruby -rubygems
# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.version               = File.read('VERSION').chomp
  gem.date                  = File.mtime('VERSION').strftime('%Y-%m-%d')

  gem.name                  = "json-ld"
  gem.homepage              = "https://github.com/ruby-rdf/json-ld"
  gem.license               = 'Unlicense'
  gem.summary               = "JSON-LD reader/writer for Ruby."
  gem.description           = "JSON::LD parses and serializes JSON-LD into RDF and implements expansion, compaction and framing API interfaces."

  gem.authors               = ['Gregg Kellogg']
  gem.email                 = 'public-linked-json@w3.org'

  gem.platform              = Gem::Platform::RUBY
  gem.files                 = %w(AUTHORS README.md UNLICENSE VERSION) + Dir.glob('lib/**/*.rb')
  gem.bindir               = %q(bin)
  gem.executables          = %w(jsonld)
  gem.require_paths         = %w(lib)
  gem.test_files            = Dir.glob('spec/**/*.rb') + Dir.glob('spec/test-files/*')

  gem.required_ruby_version = '>= 2.2.2'
  gem.requirements          = []
  gem.add_runtime_dependency     'rdf',             '~> 3.0', '>= 3.0.8'
  gem.add_runtime_dependency     'multi_json',      '~> 1.13'
  gem.add_runtime_dependency     'i18n',            '<= 1.5.1' if RUBY_VERSION < "2.3"
  gem.add_runtime_dependency     'link_header',     '~> 0.0', '>= 0.0.8'
  gem.add_runtime_dependency     'json-canonicalization', '~> 0.1'
  gem.add_runtime_dependency     'htmlentities',     '~> 4.3'
  gem.add_development_dependency 'sinatra-linkeddata','~> 3.0'
  gem.add_development_dependency 'jsonlint',        '~> 0.3'  unless RUBY_ENGINE == "jruby"
  gem.add_development_dependency 'oj',              '~> 3.8'  unless RUBY_ENGINE == "jruby"
  gem.add_development_dependency 'yajl-ruby',       '~> 1.4'  unless RUBY_ENGINE == "jruby"
  gem.add_runtime_dependency     'rack',            '>= 1.6', '< 3.0'
  gem.add_development_dependency 'rack-test',       '~> 1.1'
  gem.add_development_dependency 'rdf-isomorphic',  '~> 3.0'
  gem.add_development_dependency 'rdf-spec',        '~> 3.0'
  gem.add_development_dependency 'rdf-trig',        '~> 3.0'
  gem.add_development_dependency 'rdf-turtle',      '~> 3.0'
  gem.add_development_dependency 'rdf-vocab',       '~> 3.0'
  gem.add_development_dependency 'rdf-xsd',         '~> 3.0'
  gem.add_development_dependency 'rspec',           '~> 3.8'
  gem.add_development_dependency 'rspec-its',       '~> 1.2'
  gem.add_development_dependency 'yard' ,           '~> 0.9'

  gem.post_install_message  = nil
end
