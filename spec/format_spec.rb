# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/format'

describe JSON::LD::Format do
  before :each do
    @format_class = JSON::LD::Format
  end

  include RDF_Format

  describe ".for" do
    formats = [
      :jsonld,
      "etc/doap.jsonld",
      {:file_name      => 'etc/doap.jsonld'},
      {:file_extension => 'jsonld'},
      {:content_type   => 'application/ld+json'},
      {:content_type   => 'application/x-ld+json'},
    ].each do |arg|
      it "discovers with #{arg.inspect}" do
        RDF::Format.for(arg).should == @format_class
      end
    end

    {
      :jsonld   => '{"@context" => "foo"}',
      :context  => %({\n"@context": {),
      :id       => %({\n"@id": {),
      :type     => %({\n"@type": {),
    }.each do |sym, str|
      it "detects #{sym}" do
        @format_class.for {str}.should == @format_class
      end
    end

    it "should discover 'jsonld'" do
      RDF::Format.for(:jsonld).reader.should == JSON::LD::Reader
    end
  end

  describe "#to_sym" do
    specify {@format_class.to_sym.should == :jsonld}
  end

  describe ".detect" do
    {
      :jsonld => '{"@context" => "foo"}',
    }.each do |sym, str|
      it "detects #{sym}" do
        @format_class.detect(str).should be_true
      end
    end

    {
      :n3             => "@prefix foo: <bar> .\nfoo:bar = {<a> <b> <c>} .",
      :nquads => "<a> <b> <c> <d> . ",
      :rdfxml => '<rdf:RDF about="foo"></rdf:RDF>',
      :rdfa   => '<div about="foo"></div>',
      :microdata => '<div itemref="bar"></div>',
      :ntriples         => "<a> <b> <c> .",
      :multi_line       => '<a>\n  <b>\n  "literal"\n .',
      :turtle           => "@prefix foo: <bar> .\n foo:a foo:b <c> .",
    }.each do |sym, str|
      it "does not detect #{sym}" do
        @format_class.detect(str).should be_false
      end
    end
  end
end
