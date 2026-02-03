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
      def infer_param_type(name, default_str, fallback_type: FALLBACK_TYPE, treat_options_keyword_as_hash: true)
        return 'Array' if name.start_with?('*') && !name.start_with?('**')
        return 'Hash'  if name.start_with?('**')
        return 'Proc'  if name.start_with?('&')

        is_kw = name.end_with?(':')

        node = parse_expr(default_str)
        ty = Literals.type_from_literal(node, fallback_type: fallback_type)

        if is_kw && default_str.nil?
          return (treat_options_keyword_as_hash && name == 'options:' ? 'Hash' : fallback_type)
        end

        return 'Hash' if treat_options_keyword_as_hash && name == 'options:' && (default_str == '{}' || ty == 'Hash')

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
