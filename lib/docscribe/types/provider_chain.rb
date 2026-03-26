# frozen_string_literal: true

module Docscribe
  module Types
    # Resolve method signatures by querying a list of providers in order.
    #
    # The first provider that returns a non-nil signature wins.
    #
    # This lets Docscribe combine multiple external type sources behind one
    # interface, for example:
    # - inline Sorbet signatures in the current file
    # - Sorbet RBI files
    # - RBS files
    class ProviderChain
      # @param [Array<#signature_for>] providers ordered signature providers
      # @return [Object]
      def initialize(*providers)
        @providers = providers.compact
      end

      # Resolve a method signature from the first provider that can supply it.
      #
      # @param [String] container e.g. "MyModule::MyClass"
      # @param [Symbol] scope :instance or :class
      # @param [Symbol, String] name method name
      # @return [Docscribe::Types::MethodSignature, nil]
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
