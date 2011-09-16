module JSON::LD
  ##
  # Normalize Nodes in a graph. Uses [Normalization Algorithm](http://json-ld.org/spec/latest/#normalization-1)
  # from [JSON-LD specification](http://json-ld.org/spec/latest/).
  #
  # This module takes a graph and returns a new graph, with BNode names normalized to allow
  # for a canonical ordering of all statements within a graph.
  #
  # @example Normalize a graph
  #   JSON::LD::normalize(graph) => graph
  #
  # @see http://json-ld.org/spec/latest
  # @see http://json-ld.org/spec/latest/#normalization-1
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class Normalize
    ##
    # Create a new normalization instance
    # @param [RDF::Enumerable] graph
    def initialize(graph)
      @graph = graph
    end
    
    ##
    # Perform normalization, and return a new graph with node identifiers normalized
    # @return [RDF::Graph]
    def normalize
      # Create an empty list of expanded nodes and recursively process every object in the expanded input that is not an
      # expanded IRI, typed literal or language literal
      nodes = graph.subjects.select {|s| s.node?}
      
      forward_mapping = {}
      reverse_mapping = {}
      @node_properties = {}
      graph.each_statment do |st|
        # Create a forward mapping that relates graph nodes to the IRIs of the targets nodes that they reference. For example,
        # if a node alpha refers to a node beta via a property, the key in the forward mapping is the subject IRI of alpha and
        # the value is an array containing at least the subject IRI of beta.
        if st.subject.node? && st.object.uri?
          forward_mapping[st.subject] ||= {}
          forward_mapping[st.subject] << st.object
        end

        # Create a reverse mapping that relates graph nodes to every other node that refers to them in the graph. For example,
        # if a node alpha refers to a node beta via a property, the key in the reverse mapping is the subject IRI for beta and
        # the value is an array containing at least the IRI for alpha.
        if st.object.node? && st.subject.uri?
          reverse_mapping[st.object] ||= {}
          reverse_mapping[st.object] << st.subject
        end
        
        # For node comparisons, keep track of properties of each node
        if st.subject.node?
          @node_properties[st.subject] ||= {}
          @node_properties[st.subject][st.predicate] ||= []
          @node_properties[st.subject][st.predicate] << st.object
        end
      end
      
      # Label every unlabeled node according to the Label Generation Algorithm in descending order using the Deep
      # Comparison Algorithm to determine the sort order.
      node_mapping = {}
      gen = "c14n_1"
      nodes.sort {|a, b| deep_comparison(a) <=> deep_comparison(b) }.each do |node|
        # name with Label Generation Algorithm and create mapping from original node to new name
        node_mapping[node] = RDF::Node.new(gen)
        gen = gen.succ
      end

      # Add statements to new graph using new node names
      graph = RDF::Graph.new
      
      @graph.each_statement do |st|
        if st.subject.node? || st.object.node?
          st = st.dup
          st.subject = node_mapping.fetch(st.subject, st.subject)
          st.object = node_mapping.fetch(st.object, st.object)
        end
        graph << st
      end
      
      # Return new graph
      graph
    end
    
    private
    def shallow_comparison(a, b)
      # 1. Compare the total number of node properties. The node with fewer properties is first.
      prop_count_a = @node_properties[a].keys.length
      prop_count_b = @node_properties[b].keys.length
      return prop_count_a <=> prop_count_b unless prop_count_a == prop_count_b
      
      # 2. Lexicographically sort the property IRIs for each node and compare the sorted lists. If an IRI is found to be
      # lexicographically smaller, the node containing that IRI is first.
      p_iri_a = @node_properties[a].keys.map(&:to_s).sort.first
      p_iri_b = @node_properties[a].keys.map(&:to_s).sort.first
      return p_iri_a <=> p_iri_b unless p_iri_a == p_iri_b

      # 3. Compare the property values against one another:
      @node_properties
      alpha_list
    end
    
    def deep_comparison(a, b)
      comp = shallow_comparison(a, b)
      if comp == 0
      end
      comp
    end
  end
  
  ##
  # Normalize a graph, returning a new graph with node names normalized
  def normalize(graph)
    norm = Normalize.new
    norm.normalize
  end
  module_meathod :normalize
  
end

