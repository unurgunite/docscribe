# frozen_string_literal: true

module Docscribe
  module Infer
    # Literal inference: map simple AST literals to type names.
    module Literals
      module_function

      # Infer a type name from a literal-like AST node.
      #
      # Supports common literal/value node types such as:
      # - integers, floats, strings, symbols
      # - booleans and nil
      # - arrays, hashes, regexps
      # - constants
      # - `Foo.new` constructor calls
      #
      # If the node does not match a supported pattern, the fallback type is returned.
      #
      # @note module_function: defines #type_from_literal (visibility: private)
      # @param [Parser::AST::Node, nil] node literal/value node
      # @param [String] fallback_type type returned when inference is uncertain
      # @return [String]
      def type_from_literal(node, fallback_type: FALLBACK_TYPE)
        return fallback_type unless node

        literal_type_for(node.type) || const_type_for(node, fallback_type) ||
          send_new_type_for(node, fallback_type) || fallback_type
      end

      # Map a node type symbol to a known literal type name.
      #
      # @note module_function: defines #literal_type_for (visibility: private)
      # @param [Symbol] type node type
      # @return [String, nil]
      def literal_type_for(type)
        LITERAL_TYPE_MAP[type]
      end

      # Extract a constant name from a `:const` node.
      #
      # @note module_function: defines #const_type_for (visibility: private)
      # @param [Parser::AST::Node] node literal/value node
      # @param [String] _fallback_type fallback type string (unused here)
      # @return [String, nil]
      def const_type_for(node, _fallback_type)
        return unless node.type == :const

        node.children.last.to_s
      end

      # Extract a type from a `Foo.new` send node.
      #
      # @note module_function: defines #send_new_type_for (visibility: private)
      # @param [Parser::AST::Node] node literal/value node
      # @param [String] _fallback_type fallback type string (unused here)
      # @return [String, nil]
      def send_new_type_for(node, _fallback_type)
        return unless node.type == :send

        recv, meth, = node.children
        return unless meth == :new && recv&.type == :const

        recv.children.last.to_s
      end
    end
  end
end
