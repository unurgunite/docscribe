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
    MethodSignature = Struct.new(:return_type, :param_types, :rest_positional, :rest_keywords, keyword_init: true)

    Signature = MethodSignature

    # Simplified representation of an RBS rest-positional parameter.
    #
    # @!attribute name
    #   @return [String, nil] parameter name in RBS, if present
    # @!attribute element_type
    #   @return [String] formatted element type
    RestPositional = Struct.new(:name, :element_type, keyword_init: true)

    # Simplified representation of an RBS rest-keyword parameter.
    #
    # @!attribute name
    #   @return [String, nil] parameter name in RBS, if present
    # @!attribute type
    #   @return [String] formatted kwargs type
    RestKeywords = Struct.new(:name, :type, keyword_init: true)
  end
end
