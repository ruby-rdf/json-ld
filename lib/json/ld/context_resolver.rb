# -*- encoding: utf-8 -*-
# frozen_string_literal: true
require 'lru_redux'
require 'set'
require 'json/canonicalization'

module JSON::LD
  # Context Resolver for managing remote contexts.
  class ContextResolver
    ##
    # Defines the maximum number of interned URI references that can be held
    # cached in memory at any one time.
    CACHE_SIZE = 100 # unlimited by default

    # Maximum number of times to recursively fetch contexts
    MAX_CONTEXT_URLS = 10

    # A shared cache that may be configured for storing cached context documents.
    # Any Hash-like class responding to `#[]` and `#[]=`.
    attr_reader :shared_cache

    ##
    # Creates a ContextResolver.
    #
    # @example creating a ContextResolver instance with a custom `shared_cache` using a simple Hash for caching information.
    #   context_resolver = JSON::LD::ContextResolver.new(shared_cache: {})
    #
    # @param [Object] shared_cache (LruRedux::Cache)
    #   A shared cache that may be configured for storing cached context documents.
    # @param [Hash] options API options
    def initialize(shared_cache: LruRedux::Cache.new(CACHE_SIZE), **options)
      @per_op_cache = {}
      @shared_cache = shared_cache
      @options = options
    end

    ##
    # Resolve a context.
    # 
    # @param active_ctx the current active context.
    # @param context the context to resolve.
    # @param base the absolute URL to use for making url absolute.
    # @param cycles A set for holding contexts.
    def resolve(active_ctx, context, base, cycles=Set.new)
      base = RDF::URI(base) unless base.is_a?(RDF::URI)

      # process `@context`
      context = context['@context'] if context.is_a?(Hash) && context.has_key?('@context')

      # context is one or more contexts
      context = [context] if !context.is_a?(Array)

      # resolve each context in the array
      all_resolved = []
      context.each do |ctx|
        if ctx.respond_to?(:read)
          # Context is an IO or StringIO, read and parse
          ctx = begin
            JSON.load(ctx)
          rescue JSON::ParserError => e
            #log_debug("parse") {"Failed to parse @context from remote document at #{context}: #{e.message}"}
            raise JSON::LD::JsonLdError::InvalidRemoteContext, "Failed to parse remote context at #{ctx}: #{e.message}"
          end
            
          raise JsonLdError::InvalidRemoteContext, "#{ctx.inspect}" unless ctx.is_a?(Hash) && ctx.has_key?('@context')
          ctx = ctx['@context']
        end

        case ctx
        when String
          resolved = get(ctx) || resolve_remote_context(active_ctx, ctx, base, cycles)

          # add to output and continue
          if resolved.is_a?(Array)
            all_resolved.push(*resolved)
          else
            all_resolved.push(resolved)
          end
        when nil, false
          all_resolved.push(ResolvedContext.new(false))
        when Context
          all_resolved.push(ResolvedContext.new(ctx))
        when IO, StringIO
        when Hash
          key = ctx.to_json_c14n.hash
          if !(resolved = get(key))
            resolved = ResolvedContext.new(ctx)
            cache_resolved_context(key, resolved, 'static')
          end
          all_resolved.push(resolved)
        else
          raise JSON::LD::JsonLdError::InvalidLocalContext, "@context must be an object: #{ctx.inspect}"
        end
      end

      all_resolved
    end

  private
    # Try to get an entry for key
    def get(key)
      if !(resolved = @per_op_cache[key.to_s])
        if tag_map = shared_cache[key.to_s]
          if resolved = tag_map['static']
            @per_op_cache[key.to_s] = resolved
          end
        end
      end
      resolved
    end

    def cache_resolved_context(key, resolved, tag)
      @per_op_cache[key.to_s] = resolved.freeze
      if tag
        tag_map = shared_cache[key.to_s] ||= {}
        tag_map[tag] = resolved
      end
      resolved
    end

    def resolve_remote_context(active_ctx, url, base, cycles)
      url = base.join(url) if base
      context, remote_doc = fetch_context(active_ctx, url, cycles)

      # update base according to remote document and resolve any relative URLs
      base = remote_doc.documentUrl || url
      resolve_context_urls(context, base)

      # resolve, cache, and return context
      resolved = resolve(active_ctx, context, base, cycles)
      cache_resolved_context(url, resolved, remote_doc.tag)
      resolved
    end

    def fetch_context(active_ctx, url, cycles)
      if cycles.size > MAX_CONTEXT_URLS
        raise JSON::LD::JsonLdError::LoadingRemoteContextFailed, 'Maximum number of @context URLs exceeded.'
      end

      # check for context URL cycle
      # shortcut to avoid extra work that would eventually hit the max above
      if cycles.include?(url)
        raise JSON::LD::JsonLdError::ContextOverflow, "Cyclical @context URLs detected: #{url}."
      end

      cycles.add(url)

      url_canon = RDF::URI(url.to_s, canonicalize: true)
      url_canon.scheme = 'http' if url_canon.scheme == 'https'
      url_canon = url_canon.to_s

      if Context::PRELOADED[url_canon]
        # If this is a Proc, then replace the entry with the result of running the Proc
        if Context::PRELOADED[url_canon].respond_to?(:call)
          #log_debug("parse") {"=> (call)"}
          Context::PRELOADED[url_canon] = Context::PRELOADED[url_canon].call
        end
        remote_doc = API::RemoteDocument.new(Context::PRELOADED[url_canon], documentUrl: url_canon)
        context = Context::PRELOADED[url_canon]
      else
        begin
          remote_doc = JSON::LD::API.loadRemoteDocument(url,
            profile: 'http://www.w3.org/ns/json-ld#context',
            requestProfile: 'http://www.w3.org/ns/json-ld#context',
            **@options.merge(base: nil))
          context = remote_doc.document || url
        rescue JsonLdError::LoadingDocumentFailed => e
          raise JsonLdError::LoadingRemoteContextFailed, "#{url}: #{e.message}", e.backtrace
        rescue JsonLdError
          raise
        rescue StandardError => e
          raise JsonLdError::LoadingRemoteContextFailed, "#{url}: #{e.message}", e.backtrace
        end
      end

      # ensure ctx is an object or a pre-parsed Context
      raise JsonLdError::InvalidRemoteContext, "#{context}" unless
        context.is_a?(Context) || context.is_a?(Hash) && context.has_key?('@context')

      # append @context URL to context if given
      if remote_doc.contextUrl
        context['@context'] = [context['@context']] if !context['@context'].is_a?(Array)
        context['@context'] << remote_doc.contextUrl
      end

      [context, remote_doc]
    end

    # Resolve all relative `@context` URLs in the given context by inline
    # replacing them with absolute URLs.
    # 
    # @param context the context.
    # @param base the base IRI to use to resolve relative IRIs.
    def resolve_context_urls(context, base)
      return if !context.is_a?(Hash)
      base = RDF::URI(base) unless base.is_a?(RDF::URI)

      case ctx = context['@context']
      when String
        context['@context'] = base.join(ctx).to_s
      when Array
        ctx.each_with_index do |element, ndx|
          if element.is_a?(String)
            ctx[ndx] = base.join(element).to_s
          elsif element.is_a?(Hash)
            resolve_context_urls({'@context' => element}, base)
          end
        end
      when Hash
        # ctx is an object, resolve any context URLs in terms
        # (Iterate using keys() as items() returns a copy we can't modify)
        ctx.values.each do |definition|
          resolve_context_urls(definition, base)
        end
      end
    end
  end

  # A cached contex document, with a cache indexed by referencing active context.
  class ResolvedContext
    MAX_ACTIVE_CONTEXTS = 10

    attr_reader :document

    def initialize(document)
      @document = document
      @cache = LruRedux::Cache.new(MAX_ACTIVE_CONTEXTS)
    end

    def get_processed(active_ctx)
      raise "active_ctx has no uuid!" unless active_ctx.uuid
      @cache[active_ctx.uuid]
    end

    def set_processed(active_ctx, processed_ctx)
      @cache[active_ctx.uuid] = processed_ctx
    end

    def inspect
      v = %w([ResolvedContext)
      v << "document=#{@document}"
      v.join(" ") + "]"
    end
  end
end
