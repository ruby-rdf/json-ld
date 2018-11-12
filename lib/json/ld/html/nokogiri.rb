module JSON::LD
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
        attr_reader :node
        attr_reader :parent

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
          @node.children.all? {|c| c.text?}
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
        #def inner_text
        #  coder = HTMLEntities.new
        #  coder.decode(@node.inner_text)
        #end

        def attribute_nodes
          @attribute_nodes ||= NodeSetProxy.new(@node.attribute_nodes, self)
        end

        def xpath(*args)
          @node.xpath(*args).map do |n|
            # Get node ancestors
            parent = n.ancestors.reverse.inject(nil) do |p,node|
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
        attr_reader :node_set
        attr_reader :parent

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
      # @return [void]
      def initialize_html(input, options = {})
        require 'nokogiri' unless defined?(::Nokogiri)
        @doc = case input
        when ::Nokogiri::HTML::Document, ::Nokogiri::XML::Document
          input
        else
          begin
            require 'nokogumbo' unless defined?(::Nokogumbo)
            input = input.read if input.respond_to?(:read)
            ::Nokogiri::HTML5(input.dup.force_encoding('utf-8'), max_parse_errors: 1000)
          rescue LoadError
            ::Nokogiri::HTML.parse(input, base_uri.to_s, 'utf-8')
          end
        end
      end

      # Accessor methods to mask native elements & attributes

      ##
      # Return proxy for document root
      def root
        @root ||= NodeProxy.new(@doc.root) if @doc && @doc.root
      end

      ##
      # Document errors
      def doc_errors
        # FIXME: Nokogiri version 1.5 thinks many HTML5 elements are invalid, so just ignore all Tag errors.
        # Nokogumbo might make this simpler
        if @host_language == :html5
          @doc.errors.reject {|e| e.to_s =~ /The doctype must be the first token in the document/}
        else
          @doc.errors.reject {|e| e.to_s =~ /(?:Tag \w+ invalid)|(?:Missing attribute name)/}
        end
      end

      ##
      # Find value of document base
      #
      # @param [String] base Existing base from URI or :base_uri
      # @return [String]
      def doc_base(base)
        # find if the document has a base element
        base_el = @doc.at_css("html>head>base")
        base.join(base_el.attribute("href").to_s.split("#").first) if base_el
      end
    end
  end
end
