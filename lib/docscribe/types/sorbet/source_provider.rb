# frozen_string_literal: true

require 'docscribe/types/sorbet/prototype_provider'

module Docscribe
  module Types
    module Sorbet
      class SourceProvider < PrototypeProvider
        def initialize(source:, file:, collapse_generics: false)
          super(collapse_generics: collapse_generics)
          load_from_string(source, label: file)
        end
      end
    end
  end
end
