# frozen_string_literal: true

module Docscribe
  module Infer
    # Return type inference and rescue-conditional returns.
    module Returns
      module_function

      # Infer return type of method from its source text.
      #
      # @param method_source [String, nil]
      # @return [String]
      def infer_return_type(method_source)
        return FALLBACK_TYPE if method_source.nil? || method_source.strip.empty?

        buffer = Parser::Source::Buffer.new('(method)')
        buffer.source = method_source
        root = Docscribe::Parsing.parse_buffer(buffer)
        return FALLBACK_TYPE unless root && %i[def defs].include?(root.type)

        body = root.children.last
        last_expr_type(body) || FALLBACK_TYPE
      rescue Parser::SyntaxError
        FALLBACK_TYPE
      end

      # Infer return type from an already-parsed method node.
      #
      # @param node [Parser::AST::Node]
      # @return [String]
      def infer_return_type_from_node(node)
        body =
          case node.type
          when :def then node.children[2]
          when :defs then node.children[3]
          end

        return FALLBACK_TYPE unless body

        last_expr_type(body) || FALLBACK_TYPE
      end

      # Compute normal return type and rescue-conditional return types for a method.
      #
      # @param node [Parser::AST::Node]
      # @return [Hash{Symbol=>Object}] +{ normal: String, rescues: Array<[Array<String>, String]> }+
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

      # Infer the type of the "last expression" of a Ruby AST node.
      #
      # @param node [Parser::AST::Node, nil]
      # @return [String, nil]
      def last_expr_type(node, fallback_type:, nil_as_optional:)
        return nil unless node

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

      # Unify two inferred types conservatively.
      #
      # @param a [String, nil]
      # @param b [String, nil]
      # @return [String]
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
