require 'rubygems'

task :default => [ :spec ]

namespace :gem do
  desc "Build the json-ld-#{File.read('VERSION').chomp}.gem file"
  task :build do
    sh "gem build json-ld.gemspec && mv json-ld-#{File.read('VERSION').chomp}.gem pkg/"
  end

  desc "Release the json-ld-#{File.read('VERSION').chomp}.gem file"
  task :release do
    sh "gem push pkg/json-ld-#{File.read('VERSION').chomp}.gem"
  end
end

require 'rspec/core/rake_task'
desc 'Run specifications'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.rspec_opts = %w(--options spec/spec.opts) if File.exists?('spec/spec.opts')
end

desc "Run specs through RCov"
RSpec::Core::RakeTask.new("spec:rcov") do |spec|
  spec.rcov = true
  spec.rcov_opts =  %q[--exclude "spec"]
end

desc "Generate HTML report specs"
RSpec::Core::RakeTask.new("doc:spec") do |spec|
  spec.rspec_opts = ["--format", "html", "-o", "doc/spec.html"]
end

desc "Generate schema.org context"
task :schema_context do
  %x(
    script/gen_context http://schema.org/docs/schema_org_rdfa.html \
      --vocab http://schema.org/ \
      --prefix 'schema http://schema.org/' \
      --body --hier \
      --o etc/schema.org.jsonld
  )
end

# Presentation building
namespace :presentation do
  desc "Clean presentation files"
  task :clean do
    FileUtils.rm %w(compacted expanded framed).map {|f| "presentation/dbpedia/#{f}.jsonld"}
  end

  desc "Build presentation files"
  task :build => %w(
    presentation/dbpedia/expanded.jsonld
    presentation/dbpedia/compacted.jsonld
    presentation/dbpedia/framed.jsonld
  )

  desc "Build expanded example"
  file "presentation/dbpedia/expanded.jsonld" => %w(
    presentation/dbpedia/orig.jsonld
    presentation/dbpedia/expanded-context.jsonld) do
      system(%w(
        script/parse
          --expand presentation/dbpedia/orig.jsonld
          --context presentation/dbpedia/expanded-context.jsonld
          -o presentation/dbpedia/expanded.jsonld).join(" "))
  end

  desc "Build compacted example"
  file "presentation/dbpedia/compacted.jsonld" => %w(
    presentation/dbpedia/expanded.jsonld
    presentation/dbpedia/compact-context.jsonld) do
      system(%w(
        script/parse
          --compact presentation/dbpedia/expanded.jsonld
          --context presentation/dbpedia/compact-context.jsonld
          -o presentation/dbpedia/compacted.jsonld).join(" "))
  end

  desc "Build framed example"
  file "presentation/dbpedia/framed.jsonld" => %w(
    presentation/dbpedia/expanded.jsonld
    presentation/dbpedia/frame.jsonld) do
      system(%w(
        script/parse
          --frame presentation/dbpedia/frame.jsonld
          presentation/dbpedia/expanded.jsonld
          -o presentation/dbpedia/framed.jsonld).join(" "))
  end
end

require 'yard'
namespace :doc do
  YARD::Rake::YardocTask.new
end

task :default => :spec
task :specs => :spec
