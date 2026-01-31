# frozen_string_literal: true

module Docscribe
  module Infer
    # Name helpers: turning constant AST into strings.
    module Names
      module_function

      # Convert a constant-like AST node into a fully qualified name.
      #
      # Examples:
      # - `Foo` => "Foo"
      # - `A::B` => "A::B"
      # - `::Foo` => "::Foo"
      #
      # @param n [Parser::AST::Node, nil]
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
