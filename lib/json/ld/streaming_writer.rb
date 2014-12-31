module JSON::LD
  ##
  # Streaming writer interface.
  #
  # Writes an array of statements serialized in expanded JSON-LD. No provision for turning rdf:first/rest into @list encodings.
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  module StreamingWriter
    ##
    # Write out array start, and note not to prepend node-separating ','
    # @return [void] `self`
    def stream_prologue
      @skip_comma = true
      @output.puts "["
      self
    end

    ##
    # Write out a statement, retaining current
    # `subject` and `predicate` to create more compact output
    # @return [void] `self`
    def stream_statement(statement)
      result = node = {}
      if statement.has_context?
        result = {"@id" => statement.context.to_s, "@graph" => [node]}
      end
      node["@id"] = statement.subject.to_s
      pred = statement.predicate.to_s

      if statement.predicate == RDF.type
        node["@type"] = statement.object.to_s
      elsif statement.object.resource?
        node[pred] = [{"@id" => statement.object.to_s}]
      else
        lit = {"@value" => statement.object.to_s}
        lit["@type"] = statement.object.datatype.to_s if statement.object.has_datatype?
        lit["@language"] = statement.object.language.to_s if statement.object.has_language?
        node[pred] = [lit]
      end
      @output.puts (@skip_comma ? '  ' : ', ') + result.to_json
      @skip_comma = false
      self
    end

    ##
    # Complete open statements
    # @return [void] `self`
    def stream_epilogue
      @output.puts ']'
      self
    end
  end
end
