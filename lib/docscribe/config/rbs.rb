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
  end
end
