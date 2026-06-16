# frozen_string_literal: true

module Docscribe
  # Emit-related configuration (headers, visibility tags, etc.).
  class Config
    # Whether to emit method header lines such as:
    #   # +MyClass#foo+ -> Integer
    #
    # @return [Object]
    def emit_header?
      fetch_bool(%w[emit header], true)
    end

    # Whether to emit `@param` tags.
    #
    # @return [Object]
    def emit_param_tags?
      fetch_bool(%w[emit param_tags], true)
    end

    # Whether to emit visibility tags such as `@private` and `@protected`.
    #
    # @return [Object]
    def emit_visibility_tags?
      fetch_bool(%w[emit visibility_tags], true)
    end

    # Whether to emit inferred `@raise` tags.
    #
    # @return [Object]
    def emit_raise_tags?
      fetch_bool(%w[emit raise_tags], true)
    end

    # Whether to emit conditional rescue-return tags like:
    #   # @return [String] if FooError
    #
    # @return [Object]
    def emit_rescue_conditional_returns?
      fetch_bool(%w[emit rescue_conditional_returns], true)
    end

    # Whether to emit YARD `@!attribute` docs for `attr_*` macros.
    #
    # @return [Object]
    def emit_attributes?
      fetch_bool(%w[emit attributes], false)
    end

    # Whether to emit the `@return` tag for a method, taking per-scope and
    # per-visibility overrides into account.
    #
    # @param [Object] scope :instance or :class
    # @param [Object] visibility :public, :protected, or :private
    # @return [Object]
    def emit_return_tag?(scope, visibility)
      method_override_bool(
        scope,
        visibility,
        'return_tag',
        default: fetch_bool(%w[emit return_tag], true)
      )
    end

    # Default text inserted into generated doc blocks, taking per-scope and
    # per-visibility overrides into account.
    #
    # @param [Object] scope :instance or :class
    # @param [Object] visibility :public, :protected, or :private
    # @return [Object]
    def default_message(scope, visibility)
      method_override_str(
        scope,
        visibility,
        'default_message',
        default: raw.dig('doc', 'default_message') ||
                 DEFAULT.dig('doc', 'default_message') ||
                 'Method documentation.'
      )
    end

    # Fallback type used when inference cannot determine a more specific type.
    #
    # @return [Object, String]
    def fallback_type
      raw.dig('inference', 'fallback_type') ||
        DEFAULT.dig('inference', 'fallback_type') ||
        'Object'
    end

    # Whether unions involving nil should be rendered as optional types.
    #
    # For example, `String, nil` may become `String?` depending on formatter
    # behavior.
    #
    # @return [Object]
    def nil_as_optional?
      fetch_bool(%w[inference nil_as_optional], true)
    end

    # Whether keyword arguments named `options` / `options:` should be treated
    # specially as Hash values during inference.
    #
    # @return [Object]
    def treat_options_keyword_as_hash?
      fetch_bool(%w[inference treat_options_keyword_as_hash], true)
    end

    # Param tag syntax style.
    #
    # Supported values:
    # - `"type_name"` => `@param [String] name`
    # - `"name_type"` => `@param name [String]`
    #
    # @return [Object]
    def param_tag_style
      raw.dig('doc', 'param_tag_style') || DEFAULT.dig('doc', 'param_tag_style')
    end

    # Default generated parameter description text.
    #
    # @return [Object]
    def param_documentation
      raw.dig('doc', 'param_documentation') || DEFAULT.dig('doc', 'param_documentation')
    end

    # Whether to include the default placeholder line:
    #   # Method documentation.
    #
    # @return [Object]
    def include_default_message?
      fetch_bool(%w[emit include_default_message], true)
    end

    # Whether to append placeholder text to generated @param tags:
    #   # @param [String] name Param documentation.
    #
    # @return [Object]
    def include_param_documentation?
      fetch_bool(%w[emit include_param_documentation], true)
    end

    # Whether to preserve existing @param/@return descriptions in aggressive mode.
    #
    # @return [Object]
    def keep_descriptions?
      fetch_bool(%w[keep_descriptions], false)
    end

    # Whether to skip @param generation for anonymous block arguments (&).
    #
    # Ruby 3.2+ allows `def foo(&)`. When enabled, no @param is generated
    # for anonymous block parameters since they have no name to reference.
    #
    # @return [Object]
    def skip_anonymous_block_params?
      fetch_bool(%w[skip_anonymous_block_params], false)
    end
  end
end
