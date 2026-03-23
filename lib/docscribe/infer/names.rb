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
      # @note module_function: when included, also defines #const_full_name (instance visibility: private)
      # @param [Parser::AST::Node, nil] n constant-like AST node
      # @return [String, nil]
      def const_full_name(n)
        return nil unless n.is_a?(Parser::AST::Node)

        case n.type
        when :const
          scope, name = *n
          scope_name = const_full_name(scope)

          if scope_name && !scope_name.empty?
            "#{scope_name}::#{name}"
          elsif scope_name == '' # leading ::
            "::#{name}"
          else
            name.to_s
          end

        when :cbase
          '' # represents leading :: scope
        end
      end
    end
  end
end
