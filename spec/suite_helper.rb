require 'json/ld'
require 'open-uri'
require 'support/extensions'

# For now, override RDF::Utils::File.open_file to look for the file locally before attempting to retrieve it
module RDF::Util
  module File
    REMOTE_PATH = "http://json-ld.org/test-suite/"
    LOCAL_PATH = ::File.expand_path("../json-ld.org/test-suite", __FILE__) + '/'

    ##
    # Override to use Patron for http and https, Kernel.open otherwise.
    #
    # @param [String] filename_or_url to open
    # @param  [Hash{Symbol => Object}] options
    # @option options [Array, String] :headers
    #   HTTP Request headers.
    # @return [IO] File stream
    # @yield [IO] File stream
    def self.open_file(filename_or_url, options = {}, &block)
      case filename_or_url.to_s
      when /^file:/
        path = filename_or_url[5..-1]
        Kernel.open(path.to_s, &block)
      when /^#{REMOTE_PATH}/
        begin
          #puts "attempt to open #{filename_or_url} locally"
          local_filename = filename_or_url.to_s.sub(REMOTE_PATH, LOCAL_PATH)
          if ::File.exist?(local_filename)
            response = ::File.open(local_filename)
            #puts "use #{filename_or_url} locally"
            case filename_or_url.to_s
            when /\.jsonld$/
              def response.content_type; 'application/ld+json'; end
            when /\.sparql$/
              def response.content_type; 'application/sparql-query'; end
            end

            if block_given?
              begin
                yield response
              ensure
                response.close
              end
            else
              response
            end
          else
            Kernel.open(filename_or_url.to_s, &block)
          end
        rescue Errno::ENOENT
          # Not there, don't run tests
          StringIO.new("")
        end
      else
      end
    end
  end
end

module Fixtures
  module SuiteTest
    SUITE = RDF::URI("http://json-ld.org/test-suite/")
    class Manifest < JSON::LD::Resource
      def self.open(file)
        #puts "open: #{file}"
        RDF::Util::File.open_file(file) do |f|
          json = JSON.parse(f.read)
          self.from_jsonld(json)
        end
      end

      # @param [Hash] json framed JSON-LD
      # @return [Array<Manifest>]
      def self.from_jsonld(json)
        Manifest.new(json)
      end

      def entries
        # Map entries to resources
        attributes['sequence'].map do |e|
          e.is_a?(String) ? Manifest.open("#{SUITE}#{e}") : Entry.new(e)
        end
      end
    end

    class Entry < JSON::LD::Resource
      attr_accessor :debug

      # Base is expanded input file
      def base
        "#{SUITE}tests/#{property('input')}"
      end

      # Alias input, context, expect and frame
      %w(input context expect frame).each do |m|
        define_method(m.to_sym) {RDF::Util::File.open_file "#{SUITE}tests/#{property(m)}"}
      end

      def positiveTest
        property('positiveTest') == 'true'
      end
      
      def trace; @debug.join("\n"); end
    end
  end
end
