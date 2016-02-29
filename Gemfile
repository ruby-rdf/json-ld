source "https://rubygems.org"

gemspec
gem 'jsonlint', github: "dougbarth/jsonlint", platforms: [:rbx, :mri]

group :development do
  gem 'fasterer'
end

group :development, :test do
  gem 'simplecov', require: false
  gem 'coveralls', require: false
  gem 'psych', :platforms => [:mri, :rbx]
end

group :debug do
  gem "wirble"
  gem "byebug", platform: :mri
end

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubinius', '~> 2.0'
end
