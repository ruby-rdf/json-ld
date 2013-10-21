# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  context "Test Files" do
    Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'test-files/*-input.*'))) do |filename|
      test = File.basename(filename).sub(/-input\..*$/, '')
      frame = filename.sub(/-input\..*$/, '-frame.json')
      framed = filename.sub(/-input\..*$/, '-framed.json')
      compacted = filename.sub(/-input\..*$/, '-compacted.json')
      context = filename.sub(/-input\..*$/, '-context.json')
      expanded = filename.sub(/-input\..*$/, '-expanded.json')
      automatic = filename.sub(/-input\..*$/, '-automatic.json')
      ttl = filename.sub(/-input\..*$/, '-rdf.ttl')
      
      context test do
        it "expands" do
          options = {:debug => @debug}
          options[:expandContext] = File.open(context) if context
          jld = JSON::LD::API.expand(File.open(filename), options)
          jld.should produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(expanded)
        
        it "compacts" do
          jld = JSON::LD::API.compact(File.open(filename), File.open(context), :debug => @debug)
          jld.should produce(JSON.load(File.open(compacted)), @debug)
        end if File.exist?(compacted) && File.exist?(context)
        
        it "frame" do
          jld = JSON::LD::API.frame(File.open(filename), File.open(frame), :debug => @debug)
          jld.should produce(JSON.load(File.open(framed)), @debug)
        end if File.exist?(framed) && File.exist?(frame)

        it "toRdf" do
          RDF::Repository.load(filename, :debug => @debug).should be_equivalent_graph(RDF::Repository.load(ttl), :trace => @debug)
        end if File.exist?(ttl)
      end
    end
  end
end
