# frozen_string_literal: true

require 'English'

require 'rack'
require 'link_header'

module JSON
  module LD
    ##
    # Rack middleware for JSON-LD content negotiation.
    #
    # Uses HTTP Content Negotiation to serialize `Array` and `Hash` results as JSON-LD using 'profile' accept-params to invoke appropriate JSON-LD API methods.
    #
    # Allows black-listing and white-listing of two-part profiles where the second part denotes a URL of a _context_ or _frame_. (See {JSON::LD::Writer.accept?})
    #
    # Works along with `rack-linkeddata` for serializing data which is not in the form of an `RDF::Repository`.
    #
    #
    # @example
    #     use JSON::LD::Rack
    #
    # @see https://www.w3.org/TR/json-ld11/#iana-considerations
    # @see https://www.rubydoc.info/github/rack/rack/master/file/SPEC
    class ContentNegotiation
      VARY = { 'Vary' => 'Accept' }.freeze

      # @return [#call]
      attr_reader :app

      ##
      # * Registers JSON::LD::Rack, suitable for Sinatra application
      # * adds helpers
      #
      # @param  [Sinatra::Base] app
      # @return [void]
      def self.registered(app)
        options = {}
        app.use(JSON::LD::Rack, **options)
      end

      def initialize(app)
        @app = app
      end

      ##
      # Handles a Rack protocol request.
      # Parses Accept header to find appropriate mime-type and sets content_type accordingly.
      #
      # @param  [Hash{String => String}] env
      # @return [Array(Integer, Hash, #each)] Status, Headers and Body
      # @see    https://rubydoc.info/github/rack/rack/file/SPEC
      def call(env)
        response = app.call(env)
        body = response[2].respond_to?(:body) ? response[2].body : response[2]
        case body
        when Array, Hash
          response[2] = body # Put it back in the response, it might have been a proxy
          serialize(env, *response)
        else response
        end
      end

      ##
      # Serializes objects as JSON-LD. Defaults to expanded form, other forms
      # determined by presense of `profile` in accept-parms.
      #
      # @param  [Hash{String => String}] env
      # @param  [Integer]                status
      # @param  [Hash{String => Object}] headers
      # @param  [RDF::Enumerable]        body
      # @return [Array(Integer, Hash, #each)] Status, Headers and Body
      def serialize(env, status, headers, body)
        # This will only return json-ld content types, possibly with parameters
        content_types = parse_accept_header(env['HTTP_ACCEPT'] || 'application/ld+json')
        content_types = content_types.select do |content_type|
          _, *params = content_type.split(';').map(&:strip)
          accept_params = params.inject({}) do |memo, pv|
            p, v = pv.split('=').map(&:strip)
            memo.merge(p.downcase.to_sym => v.sub(/^["']?([^"']*)["']?$/, '\1'))
          end
          JSON::LD::Writer.accept?(accept_params)
        end
        if content_types.empty?
          not_acceptable("No appropriate combinaion of media-type and parameters found")
        else
          ct, *params = content_types.first.split(';').map(&:strip)
          accept_params = params.inject({}) do |memo, pv|
            p, v = pv.split('=').map(&:strip)
            memo.merge(p.downcase.to_sym => v.sub(/^["']?([^"']*)["']?$/, '\1'))
          end

          # Determine API method from profile
          profile = accept_params[:profile].to_s.split

          # Get context from Link header
          links = LinkHeader.parse(env['HTTP_LINK'])
          context = begin
            links.find_link(['rel', JSON_LD_NS + "context"]).href
          rescue StandardError
            nil
          end
          frame = begin
            links.find_link(['rel', JSON_LD_NS + "frame"]).href
          rescue StandardError
            nil
          end

          if profile.include?(JSON_LD_NS + "framed") && frame.nil?
            return not_acceptable("framed profile without a frame")
          end

          # accept? already determined that there are appropriate contexts
          # If profile also includes a URI which is not a namespace, use it for compaction.
          context ||= Writer.default_context if profile.include?(JSON_LD_NS + "compacted")

          result = if profile.include?(JSON_LD_NS + "flattened")
            API.flatten(body, context)
          elsif profile.include?(JSON_LD_NS + "framed")
            API.frame(body, frame)
          elsif context
            API.compact(body, context)
          elsif profile.include?(JSON_LD_NS + "expanded")
            API.expand(body)
          else
            body
          end

          headers = headers.merge(VARY).merge('Content-Type' => ct)
          [status, headers, [result.to_json]]
        end
      rescue StandardError
        http_error(500, $ERROR_INFO.message)
      end

      protected

      ##
      # Parses an HTTP `Accept` header, returning an array of MIME content
      # types ordered by the precedence rules defined in HTTP/1.1 §14.1.
      #
      # @param  [String, #to_s] header
      # @return [Array<String>]
      # @see    http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.1
      def parse_accept_header(header)
        entries = header.to_s.split(',')
        entries = entries
          .map { |e| accept_entry(e) }
          .sort_by(&:last)
          .map(&:first)
        entries.map { |e| find_content_type_for_media_range(e) }.compact
      end

      # Returns an array of quality, number of '*' in content-type, and number of non-'q' parameters
      def accept_entry(entry)
        type, *options = entry.split(';').map(&:strip)
        quality = 0 # we sort smallest first
        options.delete_if { |e| quality = 1 - e[2..].to_f if e.start_with? 'q=' }
        [options.unshift(type).join(';'), [quality, type.count('*'), 1 - options.size]]
      end

      ##
      # Returns a content type appropriate for the given `media_range`,
      # returns `nil` if `media_range` contains a wildcard subtype
      # that is not mapped.
      #
      # @param  [String, #to_s] media_range
      # @return [String, nil]
      def find_content_type_for_media_range(media_range)
        media_range = media_range.sub('*/*', 'application/ld+json') if media_range.to_s.start_with?('*/*')
        if media_range.to_s.start_with?('application/*')
          media_range = media_range.sub('application/*',
            'application/ld+json')
        end
        if media_range.to_s.start_with?('application/json')
          media_range = media_range.sub('application/json',
            'application/ld+json')
        end

        media_range.start_with?('application/ld+json') ? media_range : nil
      end

      ##
      # Outputs an HTTP `406 Not Acceptable` response.
      #
      # @param  [String, #to_s] message
      # @return [Array(Integer, Hash, #each)]
      def not_acceptable(message = nil)
        http_error(406, message, VARY)
      end

      ##
      # Outputs an HTTP `4xx` or `5xx` response.
      #
      # @param  [Integer, #to_i]         code
      # @param  [String, #to_s]          message
      # @param  [Hash{String => String}] headers
      # @return [Array(Integer, Hash, #each)]
      def http_error(code, message = nil, headers = {})
        message = [code, Rack::Utils::HTTP_STATUS_CODES[code]].join(' ') +
                  (message.nil? ? "\n" : " (#{message})\n")
        [code, { 'Content-Type' => "text/plain" }.merge(headers), [message]]
      end
    end
  end
end
