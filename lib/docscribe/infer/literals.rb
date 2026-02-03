# frozen_string_literal: true

module Docscribe
  module Infer
    # Literal inference: map simple AST literals to type names.
    module Literals
      module_function

      # Infer a type name from a literal node.
      #
      # @param node [Parser::AST::Node, nil]
      # @return [String]
      def type_from_literal(node, fallback_type: FALLBACK_TYPE)
        return fallback_type unless node

        case node.type
        when :int then 'Integer'
        when :float then 'Float'
        when :str, :dstr then 'String'
        when :sym then 'Symbol'
        when :true, :false then 'Boolean' # rubocop:disable Lint/BooleanSymbol
        when :nil then 'nil'
        when :array then 'Array'
        when :hash then 'Hash'
        when :regexp then 'Regexp'

        when :const
          node.children.last.to_s

        when :send
          recv, meth, = node.children
          if meth == :new && recv && recv.type == :const
            recv.children.last.to_s
          else
            fallback_type
          end

        else
          fallback_type
        end
      end
    end
  end
end
