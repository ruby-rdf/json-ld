source 'https://rubygems.org'

gemspec
gem 'json-canonicalization',  git: 'https://github.com/dryruby/json-canonicalization', branch: 'develop'
gem 'rdf',                    git: 'https://github.com/ruby-rdf/rdf', branch: 'develop'
gem 'nokogiri', '~> 1.15', '>= 1.15.4'

group :development do
  gem 'ebnf',               git: 'https://github.com/dryruby/ebnf',               branch: 'develop'
  gem 'json-ld-preloaded',  git: 'https://github.com/ruby-rdf/json-ld-preloaded', branch: 'develop'
  gem 'rdf-isomorphic',     git: 'https://github.com/ruby-rdf/rdf-isomorphic',    branch: 'develop'
  gem 'rdf-spec',           git: 'https://github.com/ruby-rdf/rdf-spec',          branch: 'develop'
  gem 'rdf-trig',           git: 'https://github.com/ruby-rdf/rdf-trig',          branch: 'develop'
  gem 'rdf-turtle',         git: 'https://github.com/ruby-rdf/rdf-turtle',        branch: 'develop'
  gem 'rdf-vocab',          git: 'https://github.com/ruby-rdf/rdf-vocab',         branch: 'develop'
  gem 'rdf-xsd',            git: 'https://github.com/ruby-rdf/rdf-xsd',           branch: 'develop'
  gem 'sxp',                git: 'https://github.com/dryruby/sxp.rb',             branch: 'develop'
end

group :development, :test do
  gem 'benchmark-ips'
  gem 'fasterer'
  gem 'psych', platforms: %i[mri rbx]
  gem 'rake'
  gem 'rubocop'
  gem 'rubocop-performance'
  gem 'rubocop-rspec'
  gem 'ruby-prof', platforms: :mri
  gem 'simplecov', '~> 0.22', platforms: :mri
  gem 'simplecov-lcov', '~> 0.8', platforms: :mri
end

group :debug do
  gem 'byebug', platforms: :mri
end
