# frozen_string_literal: true

module Docscribe
  module Plugin
    # Snapshot of everything known about a method at doc-generation time.
    #
    # Passed to every registered TagPlugin. Read-only — plugins must not
    # mutate the context.
    #
    # @!attribute node
    #   @return [Parser::AST::Node] the :def or :defs AST node
    # @!attribute container
    #   @return [String] e.g. "MyModule::MyClass" or "Object" for top-level
    # @!attribute scope
    #   @return [Symbol] :instance or :class
    # @!attribute visibility
    #   @return [Symbol] :public, :protected, or :private
    # @!attribute method_name
    #   @return [Symbol]
    # @!attribute inferred_params
    #   @return [Hash{String => String}] name => inferred type
    # @!attribute inferred_return
    #   @return [String] inferred return type
    # @!attribute source
    #   @return [String] raw method source text
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
