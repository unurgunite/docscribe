# frozen_string_literal: true

module Docscribe
  module Types
    # Simplified view of an RBS method signature for Docscribe.
    #
    # @!attribute return_type
    #   @return [String] formatted return type for YARD output
    # @!attribute param_types
    #   @return [Hash{String=>String}] mapping of parameter name to formatted type
    # @!attribute rest_positional
    #   @return [RestPositional, nil] info for `*args`
    # @!attribute rest_keywords
    #   @return [RestKeywords, nil] info for `**kwargs`
    #
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

    # Simplified representation of an RBS rest-positional parameter.
    #
    # @!attribute name
    #   @return [String, nil] parameter name in RBS, if present
    # @!attribute element_type
    #   @return [String] formatted element type
    #
    # @!attribute [rw] name
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] element_type
    #   @return [Object]
    #   @param [Object] value
    RestPositional = Struct.new(:name, :element_type, keyword_init: true)

    # Simplified representation of an RBS rest-keyword parameter.
    #
    # @!attribute name
    #   @return [String, nil] parameter name in RBS, if present
    # @!attribute type
    #   @return [String] formatted kwargs type
    #
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
