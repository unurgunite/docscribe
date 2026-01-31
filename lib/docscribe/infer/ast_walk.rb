# frozen_string_literal: true

module Docscribe
  module Infer
    # AST traversal helper for parser AST nodes.
    module ASTWalk
      module_function

      # Walk an AST and yield each node (preorder).
      #
      # @param node [Parser::AST::Node]
      # @yieldparam n [Parser::AST::Node]
      # @return [void]
      def walk(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        yield node
        node.children.each do |ch|
          walk(ch, &block) if ch.is_a?(Parser::AST::Node)
        end
      end
    end
  end
end
