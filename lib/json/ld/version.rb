# frozen_string_literal: true

module JSON
  module LD
    module VERSION
      VERSION_FILE = File.join(__dir__, "..", "..", "..", "VERSION")
      MAJOR, MINOR, TINY, EXTRA = File.read(VERSION_FILE).chomp.split(".")

      STRING = [MAJOR, MINOR, TINY, EXTRA].compact.join('.')

      ##
      # @return [String]
      def self.to_s
        STRING
      end

      ##
      # @return [String]
      def self.to_str
        STRING
      end

      ##
      # @return [Array(Integer, Integer, Integer)]
      def self.to_a
        STRING.split(".")
      end
    end
  end
end
