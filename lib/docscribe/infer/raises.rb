# frozen_string_literal: true

module Docscribe
  module Infer
    # Exception inference from AST (`raise`/`fail` calls and `rescue` clauses).
    module Raises
      module_function

      # Infer exception class names raised or rescued within a node.
      #
      # Sources considered:
      # - `rescue Foo, Bar`
      # - bare `rescue` (=> StandardError)
      # - `raise Foo`
      # - bare `raise` / `fail` (=> StandardError)
      #
      # Returns unique exception names in discovery order.
      #
      # @note module_function: when included, also defines #infer_raises_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node method or expression node to inspect
      # @return [Array<String>]
      def infer_raises_from_node(node)
        raises = []

        ASTWalk.walk(node) do |n|
          case n.type
          when :resbody
            exc_list = n.children[0]
            raises.concat(exception_names_from_rescue_list(exc_list))

          when :send
            recv, meth, *args = *n
            next unless recv.nil? && %i[raise fail].include?(meth)

            if args.empty?
              raises << DEFAULT_ERROR
            else
              c = Names.const_full_name(args[0])
              raises << (c || DEFAULT_ERROR)
            end
          end
        end

        raises.uniq
      end

      # Extract exception class names from a rescue exception list.
      #
      # Examples:
      # - nil => `[StandardError]`
      # - `Foo` => `["Foo"]`
      # - `[Foo, Bar]` => `["Foo", "Bar"]`
      #
      # @note module_function: when included, also defines #exception_names_from_rescue_list (instance visibility: private)
      # @param [Parser::AST::Node, nil] exc_list rescue exception list node
      # @return [Array<String>]
      def exception_names_from_rescue_list(exc_list)
        if exc_list.nil?
          [DEFAULT_ERROR]
        elsif exc_list.type == :array
          exc_list.children.map { |e| Names.const_full_name(e) || DEFAULT_ERROR }
        else
          [Names.const_full_name(exc_list) || DEFAULT_ERROR]
        end
      end
    end
  end
end
