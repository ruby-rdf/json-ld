#!/usr/bin/env ruby
require 'rubygems'
$:.unshift(File.expand_path("../../lib", __FILE__))
require "bundler/setup"
require 'json/ld'
require 'ruby-prof'
require 'getoptlong'

parser_options = {
  base:     nil,
  progress: false,
  profile:  false,
  validate: false,
}

options = {
  parser_options: parser_options,
  output:        STDOUT,
  output_format: :nquads,
  input_format:  :jsonld,
}
input = nil

OPT_ARGS = [
  ["--compact", GetoptLong::NO_ARGUMENT,              "Compact input, using context"],
  ["--context", GetoptLong::REQUIRED_ARGUMENT,        "Context used for compaction"],
  ["--expand", GetoptLong::NO_ARGUMENT,               "Expand input"],
  ["--expanded", GetoptLong::NO_ARGUMENT,             "Input is already expanded"],
  ["--flatten", GetoptLong::NO_ARGUMENT,              "Flatten input"],
  ["--frame", GetoptLong::REQUIRED_ARGUMENT,          "Frame input, option value is frame to use"],
  ["--help", "-?", GetoptLong::NO_ARGUMENT,           "This message"],
  ["--output", "-o", GetoptLong::REQUIRED_ARGUMENT,   "Where to store output (default STDOUT)"],
  ["--uri", GetoptLong::REQUIRED_ARGUMENT,            "Run with argument value as base"],
]

opts = GetoptLong.new(*OPT_ARGS.map {|o| o[0..-2]})

def usage
  STDERR.puts %{Usage: #{$0} [options] file ...}
  width = OPT_ARGS.map do |o|
    l = o.first.length
    l += o[1].length + 2 if o[1].is_a?(String)
    l
  end.max
  OPT_ARGS.each do |o|
    s = "  %-*s  " % [width, (o[1].is_a?(String) ? "#{o[0,2].join(', ')}" : o[0])]
    s += o.last
    STDERR.puts s
  end
  exit(1)
end

opts.each do |opt, arg|
  case opt
  when '--compact'      then options[:compact] = true
  when '--context'      then options[:context] = arg
  when '--expand'       then options[:expand] = true
  when '--expanded'     then options[:expanded] = true
  when '--flatten'      then options[:flatten] = true
  when '--format'       then options[:output_format] = arg.to_sym
  when '--frame'        then options[:frame] = arg
  when "--help"         then usage
  when '--output'       then options[:output] = File.open(arg, "w")
  when '--uri'          then parser_options[:base] = arg
  end
end

doc_cache = {}
la = File.read(File.expand_path("../linked-art.json", __FILE__))
doc_cache["https://linked.art/ns/v1/linked-art.json"] =
  JSON::LD::API::RemoteDocument.new(la,
    documentUrl: "https://linked.art/ns/v1/linked-art.json",
    contentType: "application/ld+json")

options[:documentLoader] = Proc.new do |url, **options, &block|
  raise "Context not pre-cached: #{url}" unless doc_cache.key?(url.to_s)
  block.call doc_cache[url.to_s]
end

all_data = JSON.parse(File.read(File.expand_path("../all_data.json", __FILE__)))

output_dir = File.expand_path("../../doc/profiles/#{File.basename __FILE__, ".rb"}", __FILE__)
FileUtils.mkdir_p(output_dir)
profile = RubyProf::Profile.new
profile.exclude_methods!(Array, :each, :map)
profile.exclude_method!(Hash, :each)
profile.exclude_method!(Kernel, :require)
profile.exclude_method!(Object, :run)
profile.exclude_common_methods!
profile.start
all_data.each do |indata|
  if options[:flatten]
    JSON::LD::API.flatten(indata, options[:context], **options)
  elsif options[:compact]
    JSON::LD::API.compact(indata, options[:context], **options)
  elsif options[:frame]
    JSON::LD::API.frame(indata, options[:frame], **options)
  else
    options[:expandContext] = options[:context]
    JSON::LD::API.expand(indata, **options)
  end
end
result = profile.stop

# Print a graph profile to text
printer = RubyProf::MultiPrinter.new(result)
printer.print(path: output_dir, profile: "profile")
puts "output saved in #{output_dir}"
