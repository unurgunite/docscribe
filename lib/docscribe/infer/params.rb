# frozen_string_literal: true

module Docscribe
  module Infer
    # Parameter type inference.
    module Params
      module_function

      # Infer a parameter type from a parameter name and optional default expression.
      #
      # Handles:
      # - positional/rest/block parameter prefixes (`*`, `**`, `&`)
      # - keyword params with and without defaults
      # - special-casing `options:` as `Hash` when enabled
      # - literal defaults via AST parsing
      #
      # @note module_function: when included, also defines #infer_param_type (instance visibility: private)
      # @param [String] name parameter name as used internally (may include `*`, `**`, `&`, or trailing `:`)
      # @param [String, nil] default_str source for the default value expression
      # @param [String] fallback_type type returned when inference is uncertain
      # @param [Boolean] treat_options_keyword_as_hash whether `options:` should be treated specially as Hash
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

      # Parse a standalone expression for parameter-default inference.
      #
      # Returns nil if the expression is empty or cannot be parsed.
      #
      # @note module_function: when included, also defines #parse_expr (instance visibility: private)
      # @param [String, nil] src expression source
      # @raise [Parser::SyntaxError]
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
