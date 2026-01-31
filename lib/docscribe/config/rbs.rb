# frozen_string_literal: true

module Docscribe
  class Config
    # Memoized RBS provider (nil if disabled or RBS is unavailable).
    #
    # @return [Docscribe::Types::RBSProvider, nil]
    def rbs_provider
      return nil unless rbs_enabled?

      @rbs_provider ||= begin
        require 'docscribe/types/rbs_provider'
        Docscribe::Types::RBSProvider.new(
          sig_dirs: rbs_sig_dirs,
          collapse_generics: rbs_collapse_generics?
        )
      rescue LoadError
        nil
      end
    end

    # @return [Boolean]
    def rbs_enabled?
      fetch_bool(%w[rbs enabled], false)
    end

    # @return [Array<String>]
    def rbs_sig_dirs
      Array(raw.dig('rbs', 'sig_dirs') || DEFAULT.dig('rbs', 'sig_dirs')).map(&:to_s)
    end

    # @return [Boolean]
    def rbs_collapse_generics?
      fetch_bool(%w[rbs collapse_generics], false)
    end
  end
end
