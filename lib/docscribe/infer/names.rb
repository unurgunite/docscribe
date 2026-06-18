# frozen_string_literal: true

module Docscribe
  module Infer
    # Constant-name helpers for turning AST nodes into fully qualified names.
    module Names
      module_function

      # Convert a `:const` / `:cbase` AST node into a fully qualified constant name.
      #
      # Examples:
      # - `Foo` => `"Foo"`
      # - `Foo::Bar` => `"Foo::Bar"`
      # - `::Foo::Bar` => `"::Foo::Bar"`
      #
      # Returns nil for unsupported nodes.
      #
      # @note module_function: defines #const_full_name (visibility: private)
      # @param [Parser::AST::Node, nil] node constant-like AST node
      # @return [String, nil]
      def const_full_name(node)
        return nil unless node.is_a?(Parser::AST::Node)

        case node.type
        when :const
          build_const_full_name(node)
        when :cbase
          ''
        end
      end

      # Build the fully qualified name from a `:const` node.
      #
      # @note module_function: defines #build_const_full_name (visibility: private)
      # @param [Parser::AST::Node] node a `:const` node
      # @return [String]
      def build_const_full_name(node)
        scope, name = *node
        scope_name = const_full_name(scope)

        if scope_name && !scope_name.empty?
          "#{scope_name}::#{name}"
        elsif scope_name == ''
          "::#{name}"
        else
          name.to_s
        end
      end
    end
  end
end
