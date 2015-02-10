#!/usr/bin/env ruby
require 'rubygems'
$:.unshift(File.expand_path("../../lib", __FILE__))
require 'json/ld'
require 'getoptlong'

def run(options)
  parser_options = options[:parser_options].merge(standard_prefixes: true)
  statement = RDF::Statement(RDF::URI("http://example/a"), RDF::URI("http://example/b"), RDF::Literal("c"))
  start = Time.new
  num = 100_000
  RDF::Writer.for(options[:output_format]).new(options[:output], parser_options) do |w|
    (1..num).each do
      w << statement
    end
  end
  secs = Time.new - start
  STDERR.puts "\nProcessed #{num} statements in #{secs} seconds @ #{num/secs} statements/second." unless options[:quiet]
end

parser_options = {
  base:     nil,
  progress: false,
  validate: false,
  stream:   false,
  strict:   false,
}

options = {
  parser_options: parser_options,
  output:         STDOUT,
  output_format:  :jsonld,
  input_format:   :jsonld,
}
input = nil

OPT_ARGS = [
  ["--output", "-o",  GetoptLong::REQUIRED_ARGUMENT,"Output to the specified file path"],
  ["--stream",        GetoptLong::NO_ARGUMENT,      "Use Streaming reader/writer"],
  ["--help", "-?",    GetoptLong::NO_ARGUMENT,      "This message"]
]
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


opts = GetoptLong.new(*OPT_ARGS.map {|o| o[0..-2]})

opts.each do |opt, arg|
  case opt
  when '--output'       then options[:output] = File.open(arg, "w")
  when '--quiet'        then options[:quiet] = true
  when '--stream'       then parser_options[:stream] = true
  when '--help'         then usage
  end
end

run(options)
