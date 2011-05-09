# coding: utf-8
$:.unshift "."
require File.join(File.dirname(__FILE__), 'spec_helper')

describe "JSON::LD::Format" do
  context "discovery" do
    {
      "json"             => RDF::Format.for(:json),
      "ld"               => RDF::Format.for(:ld),
      "etc/foaf.json"    => RDF::Format.for("etc/foaf.json"),
      "etc/foaf.ld"      => RDF::Format.for("etc/foaf.ld"),
      "foaf.json"        => RDF::Format.for(:file_name      => "foaf.json"),
      "foaf.ld"          => RDF::Format.for(:file_name      => "foaf.ld"),
      ".json"            => RDF::Format.for(:file_extension => "json"),
      ".ld"              => RDF::Format.for(:file_extension => "ld"),
      "application/json" => RDF::Format.for(:content_type   => "application/json"),
    }.each_pair do |label, format|
      it "should discover '#{label}'" do
        format.should == JSON::LD::Format
      end
    end
  end
end
