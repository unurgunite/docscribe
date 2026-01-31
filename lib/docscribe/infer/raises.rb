# frozen_string_literal: true

module Docscribe
  module Infer
    # Exception inference from AST (`raise`/`fail` and `rescue` clauses).
    module Raises
      module_function

      # Infer exception class names that the method may raise.
      #
      # @param node [Parser::AST::Node]
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

      # Convert a rescue exception list node into an array of exception class names.
      #
      # @param exc_list [Parser::AST::Node, nil]
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
