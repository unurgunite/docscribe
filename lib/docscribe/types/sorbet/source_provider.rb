# frozen_string_literal: true

require 'docscribe/types/sorbet/base_provider'

module Docscribe
  module Types
    module Sorbet
      class SourceProvider < BaseProvider
        # Method documentation.
        #
        # @param [Object] source Param documentation.
        # @param [Object] file Param documentation.
        # @param [Boolean] collapse_generics Param documentation.
        # @return [Object]
        def initialize(source:, file:, collapse_generics: false)
          super(collapse_generics: collapse_generics)
          load_from_string(source, label: file)
        end
      end
    end
  end
end
