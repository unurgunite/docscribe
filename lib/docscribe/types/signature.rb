# frozen_string_literal: true

module Docscribe
  module Types
    # @!attribute [rw] return_type
    #   @return [String]
    #   @param [String] value
    #
    # @!attribute [rw] param_types
    #   @return [Hash<String, String>]
    #   @param [Hash<String, String>] value
    #
    # @!attribute [rw] positional_types
    #   @return [Array<String>]
    #   @param [Array<String>] value
    #
    # @!attribute [rw] rest_positional
    #   @return [Docscribe::Types::RestPositional, nil]
    #   @param [Docscribe::Types::RestPositional, nil] value
    #
    # @!attribute [rw] rest_keywords
    #   @return [Docscribe::Types::RestKeywords, nil]
    #   @param [Docscribe::Types::RestKeywords, nil] value
    #
    # @!attribute [rw] overloads
    #   @return [Array<Docscribe::Types::MethodSignature>, nil]
    #   @param [Array<Docscribe::Types::MethodSignature>, nil] value
    MethodSignature = Struct.new(:return_type, :param_types, :positional_types, :rest_positional, :rest_keywords,
                                 :overloads,
                                 keyword_init: true)

    # @!attribute [rw] name
    #   @return [String, nil]
    #   @param [String, nil] value
    #
    # @!attribute [rw] element_type
    #   @return [String]
    #   @param [String] value
    RestPositional = Struct.new(:name, :element_type, keyword_init: true)

    # @!attribute [rw] name
    #   @return [String, nil]
    #   @param [String, nil] value
    #
    # @!attribute [rw] type
    #   @return [String]
    #   @param [String] value
    RestKeywords = Struct.new(:name, :type, keyword_init: true)
  end
end
