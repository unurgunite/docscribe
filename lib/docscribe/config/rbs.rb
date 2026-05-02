# frozen_string_literal: true

module Docscribe
  class Config
    # Return a memoized RBS provider if RBS integration is enabled and available.
    #
    # If RBS cannot be loaded, this returns nil and Docscribe falls back to
    # inference.
    #
    # @raise [LoadError]
    # @return [Docscribe::Types::RBS::Provider, nil]
    def rbs_provider
      return nil unless rbs_enabled?
      return nil unless ruby_supports_rbs?

      @rbs_provider ||= begin
        require 'docscribe/types/rbs/provider'
        Docscribe::Types::RBS::Provider.new(
          sig_dirs: rbs_sig_dirs,
          collapse_generics: rbs_collapse_generics?
        )
      rescue LoadError
        nil
      end
    end

    # Whether RBS integration is enabled.
    #
    # @return [Boolean]
    def rbs_enabled?
      fetch_bool(%w[rbs enabled], false)
    end

    # Signature directories used by the RBS provider.
    #
    # @return [Array<String>]
    def rbs_sig_dirs
      Array(raw.dig('rbs', 'sig_dirs') || DEFAULT.dig('rbs', 'sig_dirs')).map(&:to_s)
    end

    # Whether generic RBS types should be collapsed to simpler container names.
    #
    # Examples:
    # - `Hash<Symbol, String>` => `Hash`
    # - `Array<Integer>`       => `Array`
    #
    # @return [Boolean]
    def rbs_collapse_generics?
      fetch_bool(%w[rbs collapse_generics], false)
    end

    # Return a memoized RBS provider for core/stdlib types.
    #
    # This provider is always available when the RBS gem is installed and
    # Ruby >= 3.0, regardless of whether --rbs flag is set in user config.
    # It allows resolving return types for standard library methods like
    # Integer#+, Array#any?, etc.
    #
    # @return [Docscribe::Types::RBS::Provider, nil]
    def core_rbs_provider
      return nil unless ruby_supports_rbs?

      @core_rbs_provider ||= begin
        require 'docscribe/types/rbs/provider'
        Docscribe::Types::RBS::Provider.new(
          sig_dirs: [], # only bundled core/stdlib types
          collapse_generics: false
        )
      rescue LoadError
        nil
      end
    end

    private

    # Check if current Ruby version supports RBS.
    #
    # RBS requires Ruby 3.0+. On older versions, prints a warning and
    # returns false so callers can fall back to AST inference.
    #
    # @return [Boolean]
    def ruby_supports_rbs?
      return true if RUBY_VERSION >= '3.0'

      @rbs_warning_emitted ||= begin
        warn 'Docscribe: RBS requires Ruby 3.0+. Falling back to inference.'
        true
      end
      false
    end
  end
end
