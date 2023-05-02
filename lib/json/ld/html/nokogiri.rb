# frozen_string_literal: true

module JSON
  module LD
    class API
      ##
      # Nokogiri implementation of an HTML parser.
      #
      # @see http://nokogiri.org/
      module Nokogiri
        ##
        # Returns the name of the underlying XML library.
        #
        # @return [Symbol]
        def self.library
          :nokogiri
        end

        # Proxy class to implement uniform element accessors
        class NodeProxy
          attr_reader :node, :parent

          def initialize(node, parent = nil)
            @node = node
            @parent = parent
          end

          ##
          # Return xml:base on element, if defined
          #
          # @return [String]
          def base
            @node.attribute_with_ns("base", RDF::XML.to_s) || @node.attribute('xml:base')
          end

          def display_path
            @display_path ||= begin
              path = []
              path << parent.display_path if parent
              path << @node.name
              case @node
              when ::Nokogiri::XML::Element then path.join("/")
              when ::Nokogiri::XML::Attr    then path.join("@")
              else path.join("?")
              end
            end
          end

          ##
          # Return true of all child elements are text
          #
          # @return [Array<:text, :element, :attribute>]
          def text_content?
            @node.children.all?(&:text?)
          end

          ##
          # Children of this node
          #
          # @return [NodeSetProxy]
          def children
            NodeSetProxy.new(@node.children, self)
          end

          # Ancestors of this element, in order
          def ancestors
            @ancestors ||= parent ? parent.ancestors + [parent] : []
          end

          ##
          # Inner text of an element. Decode Entities
          #
          # @return [String]
          # def inner_text
          #  coder = HTMLEntities.new
          #  coder.decode(@node.inner_text)
          # end

          def attribute_nodes
            @attribute_nodes ||= NodeSetProxy.new(@node.attribute_nodes, self)
          end

          def xpath(*args)
            @node.xpath(*args).map do |n|
              # Get node ancestors
              parent = n.ancestors.reverse.inject(nil) do |p, node|
                NodeProxy.new(node, p)
              end
              NodeProxy.new(n, parent)
            end
          end

          ##
          # Proxy for everything else to @node
          def method_missing(method, *args)
            @node.send(method, *args)
          end
        end

        ##
        # NodeSet proxy
        class NodeSetProxy
          attr_reader :node_set, :parent

          def initialize(node_set, parent)
            @node_set = node_set
            @parent = parent
          end

          ##
          # Return a proxy for each child
          #
          # @yield child
          # @yieldparam [NodeProxy]
          def each
            @node_set.each do |c|
              yield NodeProxy.new(c, parent)
            end
          end

          ##
          # Proxy for everything else to @node_set
          def method_missing(method, *args)
            @node_set.send(method, *args)
          end
        end

        ##
        # Initializes the underlying XML library.
        #
        # @param  [Hash{Symbol => Object}] options
        # @return [NodeProxy] of root element
        def initialize_html_nokogiri(input, _options = {})
          require 'nokogiri' unless defined?(::Nokogiri)
          doc = case input
          when ::Nokogiri::HTML::Document, ::Nokogiri::XML::Document
            input
          else
            begin
              input = input.read if input.respond_to?(:read)
              ::Nokogiri::HTML5(input.force_encoding('utf-8'), max_parse_errors: 1000)
            rescue LoadError, NoMethodError
              ::Nokogiri::HTML.parse(input, base_uri.to_s, 'utf-8')
            end
          end

          NodeProxy.new(doc.root) if doc&.root
        end
        alias initialize_html initialize_html_nokogiri
      end
    end
  end
end
