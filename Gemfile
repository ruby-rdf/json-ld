source "https://rubygems.org"

gemspec
gem 'rdf',              git: "git://github.com/ruby-rdf/rdf.git",       branch: "develop"
gem 'rdf-spec',         git: "git://github.com/ruby-rdf/rdf-spec.git",  branch: "develop"
gem 'jsonlint',         git: "git://github.com/dougbarth/jsonlint.git", platforms: [:rbx, :mri]

group :development do
  gem 'ebnf',           git: "git://github.com/gkellogg/ebnf.git",        branch: "develop"
  gem 'sxp',            git: "git://github.com/gkellogg/sxp-ruby.git"
  gem 'rdf-isomorphic', git: "git://github.com/ruby-rdf/rdf-isomorphic.git", branch: "develop"
  gem 'rdf-turtle',     git: "git://github.com/ruby-rdf/rdf-turtle.git",  branch: "develop"
  gem 'rdf-trig',       git: "git://github.com/ruby-rdf/rdf-trig.git",    branch: "develop"
  gem 'rdf-vocab',      git: "git://github.com/ruby-rdf/rdf-vocab.git",   branch: "develop"
  gem 'rdf-xsd',        git: "git://github.com/ruby-rdf/rdf-xsd.git",     branch: "develop"
  gem 'fasterer'
end

group :development, :test do
  gem 'simplecov',  require: false, platform: :mri
  gem 'coveralls',  require: false, platform: :mri
  gem 'psych',      platforms: [:mri, :rbx]
end

group :debug do
  gem "wirble"
  gem "byebug", platforms: :mri
end

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubinius', '~> 2.0'
end
