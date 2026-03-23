# frozen_string_literal: true

module Docscribe
  class Config
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
          # ignore
        end

        providers << sorbet_rbi_provider
      end

      providers << rbs_provider if rbs_enabled?

      providers = providers.compact
      return nil if providers.empty?

      require 'docscribe/types/provider_chain'
      Docscribe::Types::ProviderChain.new(*providers)
    end

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

    def sorbet_enabled?
      fetch_bool(%w[sorbet enabled], false)
    end

    def sorbet_rbi_dirs
      Array(raw.dig('sorbet', 'rbi_dirs') || DEFAULT.dig('sorbet', 'rbi_dirs')).map(&:to_s)
    end

    def sorbet_collapse_generics?
      fetch_bool(%w[sorbet collapse_generics], rbs_collapse_generics?)
    end
  end
end
