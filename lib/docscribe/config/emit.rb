# frozen_string_literal: true

module Docscribe
  class Config
    # @return [Boolean]
    def emit_header?
      fetch_bool(%w[emit header], true)
    end

    # @return [Boolean]
    def emit_param_tags?
      fetch_bool(%w[emit param_tags], true)
    end

    # @return [Boolean]
    def emit_visibility_tags?
      fetch_bool(%w[emit visibility_tags], true)
    end

    # @return [Boolean]
    def emit_raise_tags?
      fetch_bool(%w[emit raise_tags], true)
    end

    # @return [Boolean]
    def emit_rescue_conditional_returns?
      fetch_bool(%w[emit rescue_conditional_returns], true)
    end

    # @return [Boolean]
    def emit_attributes?
      fetch_bool(%w[emit attributes], false)
    end

    # Whether to emit the `@return` tag for a method, accounting for per-scope/per-visibility overrides.
    #
    # @param scope [Symbol] :instance or :class
    # @param visibility [Symbol] :public, :protected, :private
    # @return [Boolean]
    def emit_return_tag?(scope, visibility)
      method_override_bool(
        scope, visibility, 'return_tag',
        default: fetch_bool(%w[emit return_tag], true)
      )
    end

    # Default text inserted into each generated doc block (can be overridden per scope/visibility).
    #
    # @param scope [Symbol]
    # @param visibility [Symbol]
    # @return [String]
    def default_message(scope, visibility)
      method_override_str(
        scope, visibility, 'default_message',
        default: raw.dig('doc', 'default_message') || DEFAULT.dig('doc', 'default_message') || 'Method documentation.'
      )
    end

    # @return [String]
    def fallback_type
      raw.dig('inference', 'fallback_type') || DEFAULT.dig('inference', 'fallback_type') || 'Object'
    end

    # @return [Boolean]
    def nil_as_optional?
      fetch_bool(%w[inference nil_as_optional], true)
    end

    # @return [Boolean]
    def treat_options_keyword_as_hash?
      fetch_bool(%w[inference treat_options_keyword_as_hash], true)
    end
  end
end
