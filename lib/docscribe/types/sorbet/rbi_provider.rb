# frozen_string_literal: true

require 'pathname'
require 'docscribe/types/sorbet/base_provider'

module Docscribe
  module Types
    module Sorbet
      class RBIProvider < BaseProvider
        # Method documentation.
        #
        # @param [Object] rbi_dirs Param documentation.
        # @param [Boolean] collapse_generics Param documentation.
        # @return [Object]
        def initialize(rbi_dirs:, collapse_generics: false)
          super(collapse_generics: collapse_generics)
          Array(rbi_dirs).each do |dir|
            path = Pathname(dir)
            next unless path.directory?

            path.glob('**/*.rbi').sort.each do |file|
              load_from_string(file.read, label: file.to_s)
            end
          end
        end
      end
    end
  end
end
