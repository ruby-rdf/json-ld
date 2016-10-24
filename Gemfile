source "https://rubygems.org"

gemspec
gem 'rdf',              github: "ruby-rdf/rdf",             branch: "develop"
gem 'rdf-spec',         github: "ruby-rdf/rdf-spec",        branch: "develop"

group :development do
  gem 'ebnf',           github: "gkellogg/ebnf",            branch: "develop"
  gem 'sxp',            github: "dryruby/sxp.rb",           branch: "develop"
  gem 'rdf-isomorphic', github: "ruby-rdf/rdf-isomorphic",  branch: "develop"
  gem 'rdf-trig',       github: "ruby-rdf/rdf-trig",        branch: "develop"
  gem 'rdf-vocab',      github: "ruby-rdf/rdf-vocab",       branch: "develop"
  gem 'rdf-xsd',        github: "ruby-rdf/rdf-xsd",         branch: "develop"
  gem 'fasterer'
end

group :development, :test do
  gem 'simplecov',  require: false, platform: :mri
  gem 'coveralls',  require: false, platform: :mri
  gem 'psych',      platforms: [:mri, :rbx]
  gem 'benchmark-ips'
end

group :debug do
  gem "byebug", platforms: :mri
end

platforms :rbx do
  gem 'rubysl',   '~> 2.0'
  gem 'rubinius', '~> 2.0'
end

platforms :jruby do
  gem 'gson',     '~> 0.6'
end
