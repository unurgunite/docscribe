# frozen_string_literal: true

module Docscribe
  class Config
    # Whether to emit method header lines such as:
    #   # +MyClass#foo+ -> Integer
    #
    # @return [Boolean]
    def emit_header?
      fetch_bool(%w[emit header], true)
    end

    # Whether to emit `@param` tags.
    #
    # @return [Boolean]
    def emit_param_tags?
      fetch_bool(%w[emit param_tags], true)
    end

    # Whether to emit visibility tags such as `@private` and `@protected`.
    #
    # @return [Boolean]
    def emit_visibility_tags?
      fetch_bool(%w[emit visibility_tags], true)
    end

    # Whether to emit inferred `@raise` tags.
    #
    # @return [Boolean]
    def emit_raise_tags?
      fetch_bool(%w[emit raise_tags], true)
    end

    # Whether to emit conditional rescue-return tags like:
    #   # @return [String] if FooError
    #
    # @return [Boolean]
    def emit_rescue_conditional_returns?
      fetch_bool(%w[emit rescue_conditional_returns], true)
    end

    # Whether to emit YARD `@!attribute` docs for `attr_*` macros.
    #
    # @return [Boolean]
    def emit_attributes?
      fetch_bool(%w[emit attributes], false)
    end

    # Whether to emit the `@return` tag for a method, taking per-scope/per-visibility
    # overrides into account.
    #
    # @param [Symbol] scope :instance or :class
    # @param [Symbol] visibility :public, :protected, or :private
    # @return [Boolean]
    def emit_return_tag?(scope, visibility)
      method_override_bool(
        scope, visibility, 'return_tag',
        default: fetch_bool(%w[emit return_tag], true)
      )
    end

    # Default text inserted into generated doc blocks, taking per-scope/per-visibility
    # overrides into account.
    #
    # @param [Symbol] scope
    # @param [Symbol] visibility
    # @return [String]
    def default_message(scope, visibility)
      method_override_str(
        scope, visibility, 'default_message',
        default: raw.dig('doc', 'default_message') || DEFAULT.dig('doc', 'default_message') || 'Method documentation.'
      )
    end

    # Fallback type used when inference cannot determine a more specific type.
    #
    # @return [String]
    def fallback_type
      raw.dig('inference', 'fallback_type') || DEFAULT.dig('inference', 'fallback_type') || 'Object'
    end

    # Whether unions involving nil should be rendered as optional types.
    #
    # For example, `String, nil` may become `String?` depending on formatter behavior.
    #
    # @return [Boolean]
    def nil_as_optional?
      fetch_bool(%w[inference nil_as_optional], true)
    end

    # Whether keyword arguments named `options`/`options:` should be treated specially as Hash.
    #
    # @return [Boolean]
    def treat_options_keyword_as_hash?
      fetch_bool(%w[inference treat_options_keyword_as_hash], true)
    end

    # Param tag syntax style.
    #
    # Supported values:
    # - `"type_name"` => `@param [String] name`
    # - `"name_type"` => `@param name [String]`
    #
    # @return [String]
    def param_tag_style
      raw.dig('doc', 'param_tag_style') || DEFAULT.dig('doc', 'param_tag_style')
    end

    # Default generated parameter description text.
    #
    # @return [String]
    def param_documentation
      raw.dig('doc', 'param_documentation') || DEFAULT.dig('doc', 'param_documentation')
    end
  end
end
