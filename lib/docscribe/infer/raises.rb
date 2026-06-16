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
      # @note module_function: defines #infer_raises_from_node (visibility: private)
      # @param [Object] node method or expression node to inspect
      # @return [Array<Elem>]
      def infer_raises_from_node(node)
        raises = [] #: Array[String]

        ASTWalk.walk(node) do |n|
          case n.type
          when :resbody
            raises.concat(exception_names_from_rescue_list(n.children[0]))
          when :send
            collect_send_raise(raises, n)
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
      # @note module_function: defines #exception_names_from_rescue_list (visibility: private)
      # @param [Object] exc_list rescue exception list node
      # @return [Array, Object, DEFAULT_ERROR, Array]
      def exception_names_from_rescue_list(exc_list)
        if exc_list.nil?
          [DEFAULT_ERROR]
        elsif exc_list.type == :array
          exc_list.children.map { |e| Names.const_full_name(e) || DEFAULT_ERROR }
        else
          [Names.const_full_name(exc_list) || DEFAULT_ERROR]
        end
      end

      # Collect exception names from a `raise` or `fail` send node.
      #
      # @note module_function: defines #collect_send_raise (visibility: private)
      # @param [Object] raises accumulator
      # @param [Object] node send node
      # @return [Object]
      def collect_send_raise(raises, node)
        recv, meth, *args = *node
        return unless recv.nil? && %i[raise fail].include?(meth)

        if args.empty?
          raises << DEFAULT_ERROR
        else
          c = Names.const_full_name(args[0])
          raises << (c || DEFAULT_ERROR)
        end
      end
    end
  end
end
