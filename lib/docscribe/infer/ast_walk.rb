# frozen_string_literal: true

module Docscribe
  module Infer
    # AST traversal helpers for parser AST nodes.
    module ASTWalk
      module_function

      # Depth-first walk over a parser AST.
      #
      # Yields each node exactly once, descending recursively through child nodes.
      # Non-AST values are ignored.
      #
      # @note module_function: when included, also defines #walk (instance visibility: private)
      # @param [Parser::AST::Node, nil] node root AST node
      # @param [Proc] block visitor block
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
