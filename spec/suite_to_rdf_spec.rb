# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require 'suite_helper'
    
    if m = Fixtures::JSONLDTest::Manifest.each.to_a.first
      m2 = m.entries.detect {|m2| m2.name == 'toRdf'}
      describe m2.name do
        m2.entries.each do |t|
          specify "#{File.basename(t.inputDocument.to_s)}: #{t.name}" do
            begin
              t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
              quads = []
              JSON::LD::API.toRDF(t.input, nil, nil,
                                  :base => t.inputDocument,
                                  :debug => t.debug) do |statement|
                quads << to_quad(statement)
              end

              quads.sort.join("").should produce(t.expect.read, t.debug)
            rescue JSON::LD::ProcessingError => e
              fail("Processing error: #{e.message}")
            rescue JSON::LD::InvalidContext => e
              fail("Invalid Context: #{e.message}")
            rescue JSON::LD::InvalidFrame => e
              fail("Invalid Frame: #{e.message}")
            end
          end
        end
      end
    end
  end

  # Don't use NQuads writer so that we don't escape Unicode
  def to_quad(thing)
    case thing
    when RDF::URI
      "<#{escaped(thing.to_s)}>"
    when RDF::Node
      escaped(thing.to_s)
    when RDF::Literal::Double
      quoted("%1.15e" % thing.value) + "^^<#{RDF::XSD.double}>"
    when RDF::Literal
      quoted(escaped(thing.value)) +
      (thing.datatype? ? "^^<#{thing.datatype}>" : "") +
      (thing.language? ? "@#{thing.language}" : "")
    when RDF::Statement
      thing.to_quad.map {|r| to_quad(r)}.compact.join(" ") + " .\n"
    end
  end

  ##
  # @param  [String] string
  # @return [String]
  def quoted(string)
    "\"#{string}\""
  end

  ##
  # @param  [String] string
  # @return [String]
  def escaped(string)
    string.gsub('\\', '\\\\').gsub("\t", '\\t').
      gsub("\n", '\\n').gsub("\r", '\\r').gsub('"', '\\"')
  end
end