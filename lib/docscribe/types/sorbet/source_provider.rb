# frozen_string_literal: true

require 'docscribe/types/sorbet/base_provider'

module Docscribe
  module Types
    module Sorbet
      # Sorbet provider for inline signatures present in the current Ruby source.
      #
      # This provider parses the source being rewritten and indexes any leading
      # `sig` declarations it can resolve through the RBS RBI prototype bridge.
      class SourceProvider < BaseProvider
        # @param [String] source Ruby source containing inline `sig` declarations
        # @param [String] file source label used in diagnostics/debug warnings
        # @param [Boolean] collapse_generics whether generic container types
        #   should be simplified during formatting
        # @return [Object]
        def initialize(source:, file:, collapse_generics: false)
          super(collapse_generics: collapse_generics)
          load_from_string(source, label: file)
        end
      end
    end
  end
end
