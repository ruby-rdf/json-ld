require 'json/ld/utils'

module JSON::LD
  module Frame
    include Utils

    ##
    # Frame input.
    #
    # @param [Array] normalized_input
    # @param [Array, Hash] expanded_frame
    # @param [Hash{Symbol => Boolean}] framing_context
    # @return [Array, Hash]
    def frame(normalized_input, expanded_frame, framing_context)
      # 2) Generate a list of frames by processing the expanded frame
      match_limit, list_of_frames, result = case expanded_frame
      when []
        # 2.2) If the expanded frame is an empty array, place an empty object into the list of frames,
        # set the JSON-LD output to an array, and set match limit to -1.
        [-1, [Hash.new], Array.new]
      when Array
        # 2.3) If the expanded frame is a non-empty array,
        # add each item in the expanded frame into the list of frames,
        # set the JSON-LD output to an array, and set match limit to -1
        [-1, expanded_frame, Array.new]
      else
        # 2.1) If the expanded frame is not an array, set match limit to 1,
        # place the expanded frame into the list of frames,
        # and set the JSON-LD output to null.
        [1, [expanded_frame], nil]
      end

      # 3) Create a match array for each expanded frame
      list_of_frames.each do |expanded_frame|
        # Halt if match_limit is zero
        last if match_limit == 0
        raise InvalidFrame::Syntax, "Expanded Frame must be an object, was #{expanded_frame.class}" unless expanded_frame.is_a?(Hash)
        
        # Add each matching item from the normalized input to the matches array and decrement the match limit by 1 if:
      end
    end
  end
end
