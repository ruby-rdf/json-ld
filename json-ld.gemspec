#!/usr/bin/env ruby -rubygems
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  gem.version            = File.read('VERSION').chomp
  gem.date               = File.mtime('VERSION').strftime('%Y-%m-%d')

  gem.name = "json-ld"
  gem.homepage = "http://rdf.rubyforge.org/json-ld"
  gem.license            = 'Public Domain' if gem.respond_to?(:license=)
  gem.summary = "JSON-LD reader/writer for Ruby."
  gem.description        = gem.summary
  gem.rubyforge_project  = 'json-ld'

  gem.authors            = ['Gregg Kellogg']
  gem.email              = 'public-rdf-ruby@w3.org'

  gem.platform           = Gem::Platform::RUBY
  gem.files              = %w(AUTHORS CREDITS README UNLICENSE VERSION) + Dir.glob('lib/**/*.rb')
  gem.bindir             = %q(bin)
  gem.executables        = %w(json_ld)
  gem.default_executable = gem.executables.first
  gem.require_paths      = %w(lib)
  gem.extensions         = %w()
  gem.test_files         = %w()
  gem.has_rdoc           = false

  gem.required_ruby_version      = '>= 1.8.1'
  gem.requirements               = []
  gem.add_runtime_dependency     'rdf',             '~> 0.4.0'
  gem.add_runtime_dependency     'json',             '>= 1.5.1'
  gem.add_development_dependency 'nokogiri' ,       '>= 1.4.4'
  gem.add_development_dependency 'yard' ,           '>= 0.6.0'
  gem.add_development_dependency 'rspec',           '>= 2.5.0'
  gem.add_development_dependency 'rdf-spec',        '~> 0.4.0'
  gem.post_install_message       = nil
end