#!/usr/bin/env ruby
require 'rubygems'
$:.unshift(File.expand_path("../../lib", __FILE__))
require "bundler/setup"
require 'json/ld'
require 'ruby-prof'

doc_cache = {}
la = File.read(File.expand_path("../linked-art.json", __FILE__))
doc_cache["https://linked.art/ns/v1/linked-art.json"] =
  JSON::LD::API::RemoteDocument.new(la,
    documentUrl: "https://linked.art/ns/v1/linked-art.json",
    contentType: "application/ld+json")

loader = Proc.new do |url, **options, &block|
  raise "Context not pre-cached" unless doc_cache.has_key?(url)
  block.call doc_cache[url]
end

all_data = JSON.parse(File.read(File.expand_path("../all_data.json", __FILE__)))

result = RubyProf.profile do
  all_data.each do |indata|
    JSON::LD::API.expand(all_data, documentLoader: loader, ordered: false)
  end
end

printer = RubyProf::GraphPrinter.new(result)
printer.print(STDOUT)