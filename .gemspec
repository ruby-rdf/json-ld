#!/usr/bin/env ruby -rubygems
# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.version               = File.read('VERSION').chomp
  gem.date                  = File.mtime('VERSION').strftime('%Y-%m-%d')

  gem.name                  = "json-ld"
  gem.homepage              = "http://github.com/gkellogg/json-ld"
  gem.license               = 'Public Domain' if gem.respond_to?(:license=)
  gem.summary               = "JSON-LD reader/writer for Ruby."
  gem.description           = "JSON::LD parses and serializes JSON-LD into RDF and implements expansion, compaction and framing API interfaces."
  gem.rubyforge_project     = 'json-ld'

  gem.authors               = ['Gregg Kellogg']
  gem.email                 = 'public-rdf-ruby@w3.org'

  gem.platform              = Gem::Platform::RUBY
  gem.files                 = %w(AUTHORS README.markdown History.markdown UNLICENSE VERSION) + Dir.glob('lib/**/*.rb')
  #gem.bindir               = %q(bin)
  #gem.executables          = %w(json_ld)
  #gem.default_executable   = gem.executables.first
  gem.require_paths         = %w(lib)
  gem.extensions            = %w()
  gem.test_files            = %w()
  gem.has_rdoc              = false

  gem.required_ruby_version = '>= 1.8.1'
  gem.requirements          = []
  gem.add_runtime_dependency     'rdf',             '>= 0.3.5'
  gem.add_runtime_dependency     'json',            '>= 1.6.5'
  gem.add_development_dependency 'equivalent-xml' , '>= 0.2.8'
  gem.add_development_dependency 'open-uri-cached', '>= 0.0.5'
  gem.add_development_dependency 'yard' ,           '>= 0.7.4'
  gem.add_development_dependency 'spira',           '>= 0.0.12'
  gem.add_development_dependency 'rspec',           '>= 2.8.0'
  gem.add_development_dependency 'rdf-spec',        '>= 0.3.5'
  gem.add_development_dependency 'rdf-turtle',      '>= 0.1.1'
  gem.add_development_dependency 'rdf-trig',        '>= 0.1.1'
  gem.add_development_dependency 'rdf-isomorphic',  '>= 0.3.4'
  gem.add_development_dependency 'sparql',          '>= 0.0.2'
  gem.add_runtime_dependency     'backports'        if RUBY_VERSION < "1.9"
  gem.post_install_message  = nil
end