# frozen_string_literal: true

module Docscribe
  class Config
    # Build the effective external signature provider chain for a given source.
    #
    # Provider precedence is:
    # 1. inline Sorbet signatures from the current source
    # 2. Sorbet RBI files
    # 3. RBS files
    #
    # Returns nil when no external type provider is enabled or available.
    #
    # @param [String] source Ruby source being rewritten
    # @param [String] file source name for diagnostics
    # @raise [LoadError]
    # @return [Docscribe::Types::ProviderChain, nil]
    def signature_provider_for(source:, file:)
      providers = []

      if sorbet_enabled?
        begin
          require 'docscribe/types/sorbet/source_provider'
          providers << Docscribe::Types::Sorbet::SourceProvider.new(
            source: source,
            file: file,
            collapse_generics: sorbet_collapse_generics?
          )
        rescue LoadError
          # Sorbet support is optional; fall back quietly.
        end

        providers << sorbet_rbi_provider
      end

      providers << rbs_provider if rbs_enabled?

      providers = providers.compact
      return nil if providers.empty?

      require 'docscribe/types/provider_chain'
      Docscribe::Types::ProviderChain.new(*providers)
    end

    # Return a memoized Sorbet RBI provider if Sorbet integration is enabled.
    #
    # @raise [LoadError]
    # @return [Docscribe::Types::Sorbet::RBIProvider, nil]
    def sorbet_rbi_provider
      return nil unless sorbet_enabled?

      @sorbet_rbi_provider ||= begin
        require 'docscribe/types/sorbet/rbi_provider'
        Docscribe::Types::Sorbet::RBIProvider.new(
          rbi_dirs: sorbet_rbi_dirs,
          collapse_generics: sorbet_collapse_generics?
        )
      rescue LoadError
        nil
      end
    end

    # Whether Sorbet support is enabled in config.
    #
    # @return [Boolean]
    def sorbet_enabled?
      fetch_bool(%w[sorbet enabled], false)
    end

    # RBI directories searched by the Sorbet provider.
    #
    # @return [Array<String>]
    def sorbet_rbi_dirs
      Array(raw.dig('sorbet', 'rbi_dirs') || DEFAULT.dig('sorbet', 'rbi_dirs')).map(&:to_s)
    end

    # Whether generic Sorbet/RBI container types should be simplified.
    #
    # Falls back to the RBS `collapse_generics` setting when Sorbet-specific
    # config is not present.
    #
    # @return [Boolean]
    def sorbet_collapse_generics?
      fetch_bool(%w[sorbet collapse_generics], rbs_collapse_generics?)
    end
  end
end
