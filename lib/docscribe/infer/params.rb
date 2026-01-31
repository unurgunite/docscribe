# frozen_string_literal: true

module Docscribe
  module Infer
    # Parameter type inference.
    module Params
      module_function

      # Infer parameter type from name and default value string.
      #
      # @param name [String]
      # @param default_str [String, nil]
      # @return [String]
      def infer_param_type(name, default_str)
        # splats and kwargs are driven by name shape
        return 'Array' if name.start_with?('*') && !name.start_with?('**')
        return 'Hash'  if name.start_with?('**')
        return 'Proc'  if name.start_with?('&')

        is_kw = name.end_with?(':')

        node = parse_expr(default_str)
        ty = Literals.type_from_literal(node)

        # Keyword arg with no default
        if is_kw && default_str.nil?
          return (name == 'options:' ? 'Hash' : FALLBACK_TYPE)
        end

        # Special-case: options: {} is typically a hash of options
        return 'Hash' if name == 'options:' && (default_str == '{}' || ty == 'Hash')

        ty
      end

      # Parse a Ruby expression from a string into an AST node.
      #
      # @param src [String, nil]
      # @return [Parser::AST::Node, nil]
      def parse_expr(src)
        return nil if src.nil? || src.strip.empty?

        buffer = Parser::Source::Buffer.new('(param)')
        buffer.source = src
        Docscribe::Parsing.parse_buffer(buffer)
      rescue Parser::SyntaxError
        nil
      end
    end
  end
end
