source "https://rubygems.org"

gemspec :name => ""
gem 'rdf',              :git => "git://github.com/ruby-rdf/rdf.git", :branch => "develop"
gem 'rdf-spec',         :git => "git://github.com/ruby-rdf/rdf-spec.git", :branch => "develop"

group :development do
  gem 'rdf-turtle',     :git => "git://github.com/ruby-rdf/rdf-turtle.git", :branch => "develop"
  gem 'rdf-trig',       :git => "git://github.com/ruby-rdf/rdf-trig.git", :branch => "develop"
  gem "linkeddata"
end

group :debug do
  gem "wirble"
  gem "debugger", :platforms => [:mri_19, :mri_20]
end

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubinius', '~> 2.0'
end
