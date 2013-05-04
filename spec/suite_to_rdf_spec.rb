# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open('http://json-ld.org/test-suite/tests/toRdf-manifest.jsonld')
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('input')}: #{t.name}" do
          begin
            t.debug = ["test: #{t.inspect}", "source: #{t.input.read}"]
            quads = JSON::LD::API.toRDF(t.input, nil, nil,
                                        :base => t.base,
                                        :debug => t.debug
            ).map do |statement|
              to_quad(statement)
            end

            sorted_expected = t.expect.readlines.sort.join("")
            quads.sort.join("").should produce(sorted_expected, t.debug)
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

  # Don't use NQuads writer so that we don't escape Unicode
  def to_quad(thing)
    case thing
    when RDF::URI
      "<#{escaped(thing.to_s)}>"
    when RDF::Node
      escaped(thing.to_s)
    when RDF::Literal::Double
      case
      when thing.object.nan?, thing.object.infinite?, thing.object.zero?
        thing.canonicalize.to_ntriples
      else
        i, f, e = ('%.15E' % thing.object.to_f).split(/[\.E]/)
        f.sub!(/0*$/, '')           # remove any trailing zeroes
        f = '0' if f.empty?         # ...but there must be a digit to the right of the decimal point
        e.sub!(/^\+?0+(\d)$/, '\1') # remove the optional leading '+' sign and any extra leading zeroes
        %("#{i}.#{f}E#{e}"^^<http://www.w3.org/2001/XMLSchema#double>)
      end
    when RDF::Literal
      v = quoted(escaped(thing.value))
      case thing.datatype
      when nil, "http://www.w3.org/2001/XMLSchema#string", "http://www.w3.org/2001/XMLSchema#langString"
        # Ignore these
      else
        v += "^^<#{thing.datatype}>"
      end
      v += "@#{thing.language}" if thing.language
      v
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
end unless ENV['CI']