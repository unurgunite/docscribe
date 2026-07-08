# frozen_string_literal: true

module Docscribe
  module Plugin
    # @!attribute [rw] node
    #   @return [Parser::AST::Node]
    #   @param [Parser::AST::Node] value
    #
    # @!attribute [rw] container
    #   @return [String]
    #   @param [String] value
    #
    # @!attribute [rw] scope
    #   @return [Symbol]
    #   @param [Symbol] value
    #
    # @!attribute [rw] visibility
    #   @return [Symbol]
    #   @param [Symbol] value
    #
    # @!attribute [rw] method_name
    #   @return [Symbol]
    #   @param [Symbol] value
    #
    # @!attribute [rw] inferred_params
    #   @return [Hash<String, String>]
    #   @param [Hash<String, String>] value
    #
    # @!attribute [rw] inferred_return
    #   @return [String]
    #   @param [String] value
    #
    # @!attribute [rw] source
    #   @return [String]
    #   @param [String] value
    Context = Struct.new(
      :node,
      :container,
      :scope,
      :visibility,
      :method_name,
      :inferred_params,
      :inferred_return,
      :source,
      keyword_init: true
    )
  end
end
