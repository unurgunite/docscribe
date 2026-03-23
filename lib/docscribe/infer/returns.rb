# frozen_string_literal: true

module Docscribe
  module Infer
    # Return type inference and rescue-conditional return extraction.
    module Returns
      module_function

      # Infer a return type from a full method definition source string.
      #
      # The source must parse to a `:def` or `:defs` node. If parsing fails or inference
      # is uncertain, the fallback type is returned.
      #
      # @note module_function: when included, also defines #infer_return_type (instance visibility: private)
      # @param [String, nil] method_source full method definition source
      # @raise [Parser::SyntaxError]
      # @return [String]
      def infer_return_type(method_source)
        return FALLBACK_TYPE if method_source.nil? || method_source.strip.empty?

        buffer = Parser::Source::Buffer.new('(method)')
        buffer.source = method_source
        root = Docscribe::Parsing.parse_buffer(buffer)
        return FALLBACK_TYPE unless root && %i[def defs].include?(root.type)

        body = root.children.last
        last_expr_type(body, fallback_type: FALLBACK_TYPE, nil_as_optional: true) || FALLBACK_TYPE
      rescue Parser::SyntaxError
        FALLBACK_TYPE
      end

      # Infer a method's normal return type from an already parsed def/defs node.
      #
      # @note module_function: when included, also defines #infer_return_type_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node `:def` or `:defs` node
      # @return [String]
      def infer_return_type_from_node(node)
        body =
          case node.type
          when :def then node.children[2]
          when :defs then node.children[3]
          end

        return FALLBACK_TYPE unless body

        last_expr_type(body, fallback_type: FALLBACK_TYPE, nil_as_optional: true) || FALLBACK_TYPE
      end

      # Return a structured return-type spec for a method node.
      #
      # The result includes:
      # - `:normal`  => normal/happy-path return type
      # - `:rescues` => array of `[exception_names, return_type]` pairs for rescue branches
      #
      # @note module_function: when included, also defines #returns_spec_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node `:def` or `:defs` node
      # @param [String] fallback_type type used when inference is uncertain
      # @param [Boolean] nil_as_optional whether `nil` unions should be rendered as optional types
      # @return [Hash]
      def returns_spec_from_node(node, fallback_type: FALLBACK_TYPE, nil_as_optional: true)
        body =
          case node.type
          when :def then node.children[2]
          when :defs then node.children[3]
          end

        spec = { normal: FALLBACK_TYPE, rescues: [] }
        return spec unless body

        if body.type == :rescue
          main_body = body.children[0]
          spec[:normal] =
            last_expr_type(main_body, fallback_type: fallback_type, nil_as_optional: nil_as_optional) || FALLBACK_TYPE

          body.children.each do |ch|
            next unless ch.is_a?(Parser::AST::Node) && ch.type == :resbody

            exc_list, _asgn, rescue_body = *ch
            exc_names = Raises.exception_names_from_rescue_list(exc_list)
            rtype =
              last_expr_type(rescue_body, fallback_type: fallback_type, nil_as_optional: nil_as_optional) ||
              fallback_type
            spec[:rescues] << [exc_names, rtype]
          end
        else
          spec[:normal] =
            last_expr_type(body, fallback_type: fallback_type, nil_as_optional: nil_as_optional) || FALLBACK_TYPE
        end

        spec
      end

      # Infer the type of the last expression in a node.
      #
      # Supports:
      # - `begin` groups
      # - `if` branches
      # - `case` expressions
      # - explicit `return`
      # - literal-like expressions via {Literals.type_from_literal}
      #
      # @note module_function: when included, also defines #last_expr_type (instance visibility: private)
      # @param [Parser::AST::Node, nil] node expression node
      # @param [String] fallback_type type used when inference is uncertain
      # @param [Boolean] nil_as_optional whether `nil` unions should be rendered as optional types
      # @return [String, nil]
      def last_expr_type(node, fallback_type:, nil_as_optional:)
        return nil unless node

        case node.type
        when :begin
          last_expr_type(node.children.last, fallback_type: fallback_type, nil_as_optional: nil_as_optional)

        when :if
          t = last_expr_type(node.children[1], fallback_type: fallback_type, nil_as_optional: nil_as_optional)
          e = last_expr_type(node.children[2], fallback_type: fallback_type, nil_as_optional: nil_as_optional)
          unify_types(t, e, fallback_type: fallback_type, nil_as_optional: nil_as_optional)

        when :case
          branches = node.children[1..].compact.flat_map do |child|
            if child.type == :when
              last_expr_type(child.children.last, fallback_type: fallback_type, nil_as_optional: nil_as_optional)
            else
              last_expr_type(child, fallback_type: fallback_type, nil_as_optional: nil_as_optional)
            end
          end.compact

          if branches.empty?
            fallback_type
          else
            branches.reduce do |a, b|
              unify_types(a, b, fallback_type: fallback_type, nil_as_optional: nil_as_optional)
            end
          end

        when :return
          Literals.type_from_literal(node.children.first, fallback_type: fallback_type)

        else
          Literals.type_from_literal(node, fallback_type: fallback_type)
        end
      end

      # Unify two inferred types into a single type string.
      #
      # Rules:
      # - identical types remain unchanged
      # - `nil` unions may become optional types if enabled
      # - otherwise falls back conservatively to `fallback_type`
      #
      # @note module_function: when included, also defines #unify_types (instance visibility: private)
      # @param [String, nil] a
      # @param [String, nil] b
      # @param [String] fallback_type
      # @param [Boolean] nil_as_optional
      # @return [String, nil]
      def unify_types(a, b, fallback_type:, nil_as_optional:)
        a ||= fallback_type
        b ||= fallback_type
        return a if a == b

        if a == 'nil' || b == 'nil'
          non_nil = (a == 'nil' ? b : a)
          return nil_as_optional ? "#{non_nil}?" : "#{non_nil}, nil"
        end

        fallback_type
      end
    end
  end
end
