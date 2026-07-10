# frozen_string_literal: true

require_relative 'overload_selector'

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
      # Initialize
      #
      # @param [Array<Docscribe::Types::_Provider>] providers ordered signature providers
      # @return [void]
      def initialize(*providers)
        @providers = providers.compact
      end

      # Resolve a method signature from the first provider that can supply it.
      #
      # When overloads are present, selects the best-matching signature.
      #
      # @param [String] container e.g. "MyModule::MyClass"
      # @param [Symbol] scope :instance or :class
      # @param [Symbol, String] name method name
      # @param [Integer?] param_count number of actual arguments
      # @param [Array<String>] param_names actual parameter names
      # @return [Docscribe::Types::MethodSignature, nil]
      def signature_for(container:, scope:, name:, param_count: nil, param_names: [])
        @providers.each do |provider|
          sig = provider.signature_for(container: container, scope: scope, name: name)
          next unless sig

          return sig unless sig.overloads&.any?

          best = select_overload(sig, param_count, param_names)
          return best if best
        end

        nil
      end

      # @param [Docscribe::Types::MethodSignature] sig
      # @param [Integer?] param_count
      # @param [Array<String>] param_names
      # @return [Docscribe::Types::MethodSignature, nil]
      def select_overload(sig, param_count, param_names)
        OverloadSelector.select(
          [sig, *sig.overloads],
          arg_count: param_count || 0,
          param_names: param_names
        )
      end
    end
  end
end
