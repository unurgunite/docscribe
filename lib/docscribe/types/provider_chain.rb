# frozen_string_literal: true

module Docscribe
  module Types
    class ProviderChain
      def initialize(*providers)
        @providers = providers.compact
      end

      def signature_for(container:, scope:, name:)
        @providers.each do |provider|
          sig = provider.signature_for(container: container, scope: scope, name: name)
          return sig if sig
        end

        nil
      end
    end
  end
end
