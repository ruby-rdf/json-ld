require 'rubygems'

task default: [ :spec ]

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

desc "Generate schema.org context"
task :schema_context do
  %x(
    script/gen_context https://schema.org/docs/schema_org_rdfa.html \
      --vocab http://schema.org/ \
      --prefix 'schema http://schema.org/' \
      --body --hier \
      --o etc/schema.org.jsonld
  )
end

desc "Create concatenated test manifests"
file "etc/manifests.nt" do
  require 'rdf'
  require 'json/ld'
  require 'rdf/ntriples'
  graph = RDF::Graph.new do |g|
    %w( https://w3c.github.io/json-ld-api/tests/compact-manifest.jsonld
        https://w3c.github.io/json-ld-api/tests/expand-manifest.jsonld
        https://w3c.github.io/json-ld-api/tests/flatten-manifest.jsonld
        https://w3c.github.io/json-ld-api/tests/fromRdf-manifest.jsonld
        https://w3c.github.io/json-ld-api/tests/html-manifest.jsonld
        https://w3c.github.io/json-ld-api/tests/remote-doc-manifest.jsonld
        https://w3c.github.io/json-ld-api/tests/toRdf-manifest.jsonld
        https://w3c.github.io/json-ld-framing/tests/frame-manifest.jsonld
    ).each do |man|
      puts "load #{man}"
      g.load(man, unique_bnodes: true)
    end
  end
  puts "write"
  RDF::NTriples::Writer.open("etc/manifests.nt", unique_bnodes: true, validate: false) {|w| w << graph}
end

# Presentation building
namespace :presentation do
  desc "Clean presentation files"
  task :clean do
    FileUtils.rm %w(compacted expanded framed).map {|f| "presentation/dbpedia/#{f}.jsonld"}
  end

  desc "Build presentation files"
  task build: %w(
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

task default: :spec
task specs: :spec
