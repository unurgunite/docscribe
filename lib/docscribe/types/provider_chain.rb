# frozen_string_literal: true

module Docscribe
  module Types
    class ProviderChain
      # Method documentation.
      #
      # @param [Array] providers Param documentation.
      # @return [Object]
      def initialize(*providers)
        @providers = providers.compact
      end

      # Method documentation.
      #
      # @param [Object] container Param documentation.
      # @param [Object] scope Param documentation.
      # @param [Object] name Param documentation.
      # @return [nil]
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
