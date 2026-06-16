# frozen_string_literal: true

module Docscribe
  # Sorbet and signature provider configuration.
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
    # @param [Object] source Ruby source being rewritten
    # @param [Object] file source name for diagnostics
    # @return [Object]
    def signature_provider_for(source:, file:)
      providers = [] #: Array[untyped]
      append_sorbet_providers(providers, source: source, file: file)
      providers << rbs_provider if rbs_enabled?
      build_provider_chain(providers)
    end

    # Append Sorbet-based providers to the list.
    #
    # @param [Object] providers Param documentation.
    # @param [Object] source Ruby source being rewritten
    # @param [Object] file source name for diagnostics
    # @return [Object]
    def append_sorbet_providers(providers, source:, file:)
      return unless sorbet_enabled?

      providers << sorbet_source_provider(source, file)
      providers << sorbet_rbi_provider
    end

    # Build a Sorbet source provider (inline sigs).
    #
    # @param [Object] source Ruby source being rewritten
    # @param [Object] file source name for diagnostics
    # @raise [LoadError]
    # @return [SourceProvider] if LoadError
    # @return [nil] if LoadError
    def sorbet_source_provider(source, file)
      require 'docscribe/types/sorbet/source_provider'
      Docscribe::Types::Sorbet::SourceProvider.new(
        source: source,
        file: file,
        collapse_generics: sorbet_collapse_generics?
      )
    rescue LoadError
      nil
    end

    # Build the provider chain from a non-empty list, or return nil.
    #
    # @param [Object] providers Param documentation.
    # @return [ProviderChain]
    def build_provider_chain(providers)
      providers = providers.compact
      return nil if providers.empty?

      require 'docscribe/types/provider_chain'
      Docscribe::Types::ProviderChain.new(*providers)
    end

    # Return a memoized Sorbet RBI provider if Sorbet integration is enabled.
    #
    # @raise [LoadError]
    # @return [Object]
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
    # @return [Object]
    def sorbet_enabled?
      fetch_bool(%w[sorbet enabled], false)
    end

    # RBI directories searched by the Sorbet provider.
    #
    # @return [Object]
    def sorbet_rbi_dirs
      Array(raw.dig('sorbet', 'rbi_dirs') || DEFAULT.dig('sorbet', 'rbi_dirs')).map(&:to_s) # steep:ignore
    end

    # Whether generic Sorbet/RBI container types should be simplified.
    #
    # Falls back to the RBS `collapse_generics` setting when Sorbet-specific
    # config is not present.
    #
    # @return [Object]
    def sorbet_collapse_generics?
      fetch_bool(%w[sorbet collapse_generics], rbs_collapse_generics?)
    end
  end
end
