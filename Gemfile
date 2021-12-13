source "https://rubygems.org"
gem "nokogiri",       '~> 1.10'

gemspec
gem 'rdf',                  git: "https://github.com/ruby-rdf/rdf",                 branch: "develop"
gem 'json-canonicalization',git: "https://github.com/dryruby/json-canonicalization",branch: "develop"

group :development do
  gem 'ebnf',               git: "https://github.com/dryruby/ebnf",                 branch: "develop"
  gem 'json-ld-preloaded',  github: "ruby-rdf/json-ld-preloaded",   branch: "develop"
  gem 'ld-patch',           github: "ruby-rdf/ld-patch",            branch: "develop"
  gem 'linkeddata',         git: "https://github.com/ruby-rdf/linkeddata",          branch: "develop"
  gem 'rack-linkeddata',    git: "https://github.com/ruby-rdf/rack-linkeddata",     branch: "develop"
  gem 'rdf-aggregate-repo', git: "https://github.com/ruby-rdf/rdf-aggregate-repo",  branch: "develop"
  gem 'rdf-isomorphic',     git: "https://github.com/ruby-rdf/rdf-isomorphic",      branch: "develop"
  gem 'rdf-json',           github: "ruby-rdf/rdf-json",            branch: "develop"
  gem 'rdf-microdata',      git: "https://github.com/ruby-rdf/rdf-microdata",       branch: "develop"
  gem 'rdf-n3',             github: "ruby-rdf/rdf-n3",              branch: "develop"
  gem 'rdf-normalize',      github: "ruby-rdf/rdf-normalize",       branch: "develop"
  gem 'rdf-rdfa',           git: "https://github.com/ruby-rdf/rdf-rdfa",            branch: "develop"
  gem 'rdf-rdfxml',         git: "https://github.com/ruby-rdf/rdf-rdfxml",          branch: "develop"
  gem 'rdf-reasoner',       github: "ruby-rdf/rdf-reasoner",        branch: "develop"
  gem 'rdf-spec',           git: "https://github.com/ruby-rdf/rdf-spec",            branch: "develop"
  gem 'rdf-tabular',        github: "ruby-rdf/rdf-tabular",         branch: "develop"
  gem 'rdf-trig',           git: "https://github.com/ruby-rdf/rdf-trig",            branch: "develop"
  gem 'rdf-trix',           github: "ruby-rdf/rdf-trix",            branch: "develop"
  gem 'rdf-turtle',         git: "https://github.com/ruby-rdf/rdf-turtle",          branch: "develop"
  gem 'rdf-vocab',          git: "https://github.com/ruby-rdf/rdf-vocab",           branch: "develop"
  gem 'rdf-xsd',            git: "https://github.com/ruby-rdf/rdf-xsd",             branch: "develop"
  gem 'sinatra-linkeddata', git: "https://github.com/ruby-rdf/sinatra-linkeddata",  branch: "develop"
  gem 'shex',               github: "ruby-rdf/shex",                branch: "develop"
  gem 'sparql',             git: "https://github.com/ruby-rdf/sparql",              branch: "develop"
  gem 'sparql-client',      git: "https://github.com/ruby-rdf/sparql-client",       branch: "develop"
  gem 'sxp',                git: "https://github.com/dryruby/sxp.rb",               branch: "develop"
  gem 'fasterer'
  gem 'earl-report'
  gem 'ruby-prof',  platforms: :mri
end

group :development, :test do
  gem 'simplecov', '~> 0.21',  platforms: :mri
  gem 'simplecov-lcov', '~> 0.8',  platforms: :mri
  gem 'psych',      platforms: [:mri, :rbx]
  gem 'benchmark-ips'
  gem 'rake'
end

group :debug do
  gem "byebug", platforms: :mri
end
