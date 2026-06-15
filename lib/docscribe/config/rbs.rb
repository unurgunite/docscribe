# frozen_string_literal: true

module Docscribe
  # RBS signature provider configuration.
  class Config
    # Return a memoized RBS provider if RBS integration is enabled and available.
    #
    # If RBS cannot be loaded, this returns nil and Docscribe falls back to
    # inference.
    #
    # @return [Docscribe::Types::RBS::Provider, nil]
    def rbs_provider
      return nil unless rbs_enabled?
      return nil unless ruby_supports_rbs?

      @rbs_provider ||= build_rbs_provider
    end

    # Whether RBS integration is enabled.
    #
    # @return [Boolean]
    def rbs_enabled?
      fetch_bool(%w[rbs enabled], false)
    end

    # Core rbs provider
    #
    # @return [Docscribe::Types::RBS::Provider, nil]
    def core_rbs_provider
      return nil unless ruby_supports_rbs?

      @core_rbs_provider ||= build_core_rbs_provider
    end

    private

    # Check whether the current Ruby version supports RBS (requires 3.0+).
    #
    # @private
    # @return [Boolean]
    def ruby_supports_rbs?
      return true if RUBY_VERSION >= '3.0'

      @rbs_warning_emitted ||= begin
        warn 'Docscribe: RBS requires Ruby 3.0+. Falling back to inference.'
        true
      end
      false
    end

    # Build rbs provider
    #
    # @private
    # @raise [LoadError]
    # @return [Docscribe::Types::RBS::Provider, nil] if LoadError
    # @return [nil] if LoadError
    def build_rbs_provider
      require 'docscribe/types/rbs/provider'
      Docscribe::Types::RBS::Provider.new(
        sig_dirs: rbs_sig_dirs,
        collection_dirs: rbs_collection_dirs,
        collapse_generics: rbs_collapse_generics?
      )
    rescue LoadError
      warn 'Docscribe: --rbs requires the `rbs` gem. Add `gem "rbs"` to your Gemfile and run `bundle install`.'
      nil
    end

    # Build core rbs provider
    #
    # @private
    # @raise [LoadError]
    # @return [Docscribe::Types::RBS::Provider, nil] if LoadError
    # @return [nil] if LoadError
    def build_core_rbs_provider
      require 'docscribe/types/rbs/provider'
      Docscribe::Types::RBS::Provider.new(
        sig_dirs: [],
        collapse_generics: false
      )
    rescue LoadError
      warn 'Docscribe: --rbs requires the `rbs` gem. Add `gem "rbs"` to your Gemfile and run `bundle install`.'
      nil
    end

    # Signature directories used by the RBS provider.
    #
    # @private
    # @return [Array<String>]
    def rbs_sig_dirs
      Array(raw.dig('rbs', 'sig_dirs') || DEFAULT.dig('rbs', 'sig_dirs')).map(&:to_s)
    end

    # RBS collection directories (auto-discovered from rbs_collection.lock.yaml).
    #
    # Loaded separately from user sig_dirs so that collection-related
    # RBS environment errors (e.g. duplicate declarations against core
    # stdlib types) do not silence all RBS lookups.
    #
    # @private
    # @return [Array<String>]
    def rbs_collection_dirs
      Array(raw.dig('rbs', 'collection_dirs')).map(&:to_s)
    end

    # Whether generic RBS types should be collapsed to simpler container names.
    #
    # Examples:
    # - `Hash<Symbol, String>` => `Hash`
    # - `Array<Integer>`       => `Array`
    #
    # @private
    # @return [Boolean]
    def rbs_collapse_generics?
      fetch_bool(%w[rbs collapse_generics], false)
    end
  end
end
