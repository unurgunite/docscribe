# frozen_string_literal: true

module Docscribe
  module Infer
    # Parameter type inference.
    module Params
      module_function

      # Infer a parameter type from an internal parameter name representation and
      # an optional default expression.
      #
      # Handles:
      # - positional/rest/block parameter prefixes (`*`, `**`, `&`)
      # - keyword params with and without defaults
      # - special-casing `options:` as `Hash` when enabled
      # - literal defaults via AST parsing
      #
      # @note module_function: defines #infer_param_type (visibility: private)
      # @param [Object] name parameter name as used internally (may include `*`, `**`, `&`, or trailing `:`)
      # @param [Object] default_str source for the default value expression
      # @param [FALLBACK_TYPE] fallback_type type returned when inference is uncertain
      # @param [Boolean] treat_options_keyword_as_hash whether `options:` should
      # @return [Object]
      def infer_param_type(name, default_str, fallback_type: FALLBACK_TYPE, treat_options_keyword_as_hash: true)
        prefix_param_type(name) || inferred_param_type(name, default_str, fallback_type,
                                                       treat_options_keyword_as_hash: treat_options_keyword_as_hash)
      end

      # Return type for special parameter prefixes.
      #
      # @note module_function: defines #prefix_param_type (visibility: private)
      # @param [Object] name parameter name
      # @return [nil]
      def prefix_param_type(name)
        return 'Array' if name.start_with?('*') && !name.start_with?('**')
        return 'Hash'  if name.start_with?('**')
        return 'Proc'  if name.start_with?('&')

        nil
      end

      # Infer type for a regular or keyword parameter with optional default.
      #
      # @note module_function: defines #inferred_param_type (visibility: private)
      # @param [Object] name parameter name
      # @param [Object] default_str default expression source
      # @param [Object] fallback_type type returned when not special-cased
      # @param [Object] treat_options_keyword_as_hash whether to treat 'options:' as Hash
      # @return [Object]
      def inferred_param_type(name, default_str, fallback_type, treat_options_keyword_as_hash:)
        if name.end_with?(':') && default_str.nil?
          return options_keyword_type(name, treat_options_keyword_as_hash, fallback_type)
        end

        node = parse_expr(default_str)
        ty = Literals.type_from_literal(node, fallback_type: fallback_type)

        return 'Hash' if options_hash_keyword?(name, default_str, ty, treat_options_keyword_as_hash)

        ty
      end

      # Return 'Hash' for a keyword parameter named 'options:' when special-cased, else fallback.
      #
      # @note module_function: defines #options_keyword_type (visibility: private)
      # @param [Object] name parameter name
      # @param [Object] treat_options_keyword_as_hash whether to treat 'options:' as Hash
      # @param [Object] fallback_type type returned when not special-cased
      # @return [String, Object]
      def options_keyword_type(name, treat_options_keyword_as_hash, fallback_type)
        treat_options_keyword_as_hash && name == 'options:' ? 'Hash' : fallback_type
      end

      # Whether a keyword parameter named 'options:' with a hash default should be typed as Hash.
      #
      # @note module_function: defines #options_hash_keyword? (visibility: private)
      # @param [Object] name parameter name
      # @param [Object] default_str default expression source
      # @param [Object] type inferred type
      # @param [Object] treat_options_keyword_as_hash whether to treat 'options:' as Hash
      # @return [Object, Boolean, Boolean]
      def options_hash_keyword?(name, default_str, type, treat_options_keyword_as_hash)
        treat_options_keyword_as_hash && name == 'options:' && (default_str == '{}' || type == 'Hash')
      end

      # Parse a standalone expression for parameter-default inference.
      #
      # Returns nil if the expression is empty or cannot be parsed.
      #
      # @note module_function: defines #parse_expr (visibility: private)
      # @param [Object] src expression source
      # @raise [Parser::SyntaxError]
      # @return [Object]
      # @return [nil] if Parser::SyntaxError
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
