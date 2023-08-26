#!/usr/bin/env ruby -rubygems
# frozen_string_literal: true

is_java = RUBY_PLATFORM == 'java'

Gem::Specification.new do |gem|
  gem.version               = File.read('VERSION').chomp

  gem.name                  = "json-ld"
  gem.homepage              = "https://github.com/ruby-rdf/json-ld"
  gem.license               = 'Unlicense'
  gem.summary               = "JSON-LD reader/writer for Ruby."
  gem.description           = "JSON::LD parses and serializes JSON-LD into RDF and implements expansion, compaction and framing API interfaces for the Ruby RDF.rb library suite."
  gem.metadata = {
    "documentation_uri" => "https://ruby-rdf.github.io/json-ld",
    "bug_tracker_uri" => "https://github.com/ruby-rdf/json-ld/issues",
    "homepage_uri" => "https://github.com/ruby-rdf/json-ld",
    "mailing_list_uri" => "https://lists.w3.org/Archives/Public/public-rdf-ruby/",
    "source_code_uri" => "https://github.com/ruby-rdf/json-ld",
    'rubygems_mfa_required' => 'true'
  }

  gem.authors               = ['Gregg Kellogg']
  gem.email                 = 'public-linked-json@w3.org'

  gem.platform              = Gem::Platform::RUBY
  gem.files                 = %w[AUTHORS README.md UNLICENSE VERSION] + Dir.glob('lib/**/*.rb')
  gem.bindir               = 'bin'
  gem.executables          = %w[jsonld]
  gem.require_paths         = %w[lib]

  gem.required_ruby_version = '>= 3.0'
  gem.requirements          = []
  gem.add_runtime_dependency     'htmlentities', '~> 4.3'
  gem.add_runtime_dependency     'json-canonicalization', '~> 0.3', '>= 0.3.2'
  gem.add_runtime_dependency     'link_header', '~> 0.0', '>= 0.0.8'
  gem.add_runtime_dependency     'multi_json',      '~> 1.15'
  gem.add_runtime_dependency     "rack",            '>= 2.2', '< 4'
  gem.add_runtime_dependency     'rdf',             '~> 3.3'
  gem.add_development_dependency 'jsonlint',        '~> 0.4'  unless is_java
  gem.add_development_dependency 'oj',              '~> 3.15' unless is_java
  gem.add_development_dependency 'rack-test',       '~> 2.1'
  gem.add_development_dependency 'rdf-isomorphic',  '~> 3.2'
  gem.add_development_dependency 'rdf-spec',        '~> 3.2'
  gem.add_development_dependency 'rdf-trig',        '~> 3.2'
  gem.add_development_dependency 'rdf-turtle',      '~> 3.2'
  gem.add_development_dependency 'rdf-vocab',       '~> 3.2'
  gem.add_development_dependency 'rdf-xsd',         '~> 3.2'
  gem.add_development_dependency 'rspec',           '~> 3.12'
  gem.add_development_dependency 'rspec-its',       '~> 1.3'
  gem.add_development_dependency 'sinatra-linkeddata', '~> 3.2'
  gem.add_development_dependency 'yajl-ruby',       '~> 1.4' unless is_java
  gem.add_development_dependency 'yard', '~> 0.9'

  gem.post_install_message = nil
end
