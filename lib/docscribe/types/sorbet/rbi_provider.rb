# frozen_string_literal: true

require 'pathname'
require 'docscribe/types/sorbet/base_provider'

module Docscribe
  module Types
    module Sorbet
      # Sorbet provider that loads signatures from RBI directories.
      #
      # Each configured directory is scanned recursively for `.rbi` files, and
      # any signatures that can be parsed are indexed into Docscribe's normalized
      # signature model.
      class RBIProvider < BaseProvider
        # @param [Array<String>] rbi_dirs directories scanned recursively for
        #   `.rbi` files
        # @param [Boolean] collapse_generics whether generic container types
        #   should be simplified during formatting
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
