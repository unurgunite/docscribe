# frozen_string_literal: true

module Docscribe
  module Types
    # @!attribute [rw] return_type
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] param_types
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] rest_positional
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] rest_keywords
    #   @return [Object]
    #   @param [Object] value
    MethodSignature = Struct.new(:return_type, :param_types, :rest_positional, :rest_keywords, keyword_init: true)

    # @!attribute [rw] name
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] element_type
    #   @return [Object]
    #   @param [Object] value
    RestPositional = Struct.new(:name, :element_type, keyword_init: true)

    # @!attribute [rw] name
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] type
    #   @return [Object]
    #   @param [Object] value
    RestKeywords = Struct.new(:name, :type, keyword_init: true)
  end
end
