# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::Resource do
  subject {JSON::LD::Resource.new({'@id' => '_:foo', "http://schema.org/name" => "foo"})}
  describe "#initialize" do
    specify {expect(subject).not_to be_nil}
    specify {expect(subject).to be_a(JSON::LD::Resource)}
    specify {expect(subject).not_to be_clean}
    specify {expect(subject).to be_anonymous}
    specify {expect(subject).to be_dirty}
    specify {expect(subject).to be_new}
    specify {expect(subject).not_to be_resolved}
    specify {expect(subject).not_to be_stub}
    context "schema:name property" do
      specify {expect(subject.property("http://schema.org/name")).to eq "foo"}
    end

    describe "compacted with context" do
      subject {JSON::LD::Resource.new({'@id' => '_:foo', "http://schema.org/name" => "foo"}, :compact => true, :context => {"@vocab" => "http://schema.org/"})}
      specify {expect(subject).not_to be_nil}
      specify {expect(subject).to be_a(JSON::LD::Resource)}
      specify {expect(subject).not_to be_clean}
      specify {expect(subject).to be_anonymous}
      specify {expect(subject).to be_dirty}
      specify {expect(subject).to be_new}
      specify {expect(subject).not_to be_resolved}
      specify {expect(subject).not_to be_stub}
      its(:name) {should eq "foo"}
    end
  end

  describe "#deresolve" do
    it "FIXME"
  end

  describe "#resolve" do
    it "FIXME"
  end

  describe "#hash" do
    specify {subject.hash.should be_a(Fixnum)}
      
    it "returns the hash of the attributes" do
      subject.hash.should == subject.deresolve.hash
    end
  end

  describe "#to_json" do
    it "has JSON" do
      subject.to_json.should be_a(String)
      JSON.parse(subject.to_json).should be_a(Hash)
    end
    it "has same ID" do
      JSON.parse(subject.to_json)['@id'].should == subject.id
    end
  end

  describe "#each" do
    specify {expect {|b| subject.each(&b)}.to yield_with_args(RDF::Statement)}
  end

  describe RDF::Enumerable do
    specify {expect(subject).to be_enumerable}

    it "initializes a graph" do
      g = RDF::Graph.new << subject
      expect(g.count).to eq 1
      expect(g.objects.first).to eq "foo"
    end
  end

  describe "#save" do
    specify {expect {subject.save}.to raise_error(NotImplementedError)}
  end
end
