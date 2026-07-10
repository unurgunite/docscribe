# frozen_string_literal: true

module Docscribe
  module Types
    # Selects best matching overload from RBS signatures for given arguments.
    module OverloadSelector
      class << self
        # @param [Array<Object>] overloads
        # @param [Integer] arg_count
        # @param [Array<String>] param_names
        # @return [Object?]
        def select(overloads, arg_count:, param_names: [])
          return nil if overloads.nil? || overloads.empty?
          return overloads.first if overloads.size == 1

          best = best_match(overloads, arg_count, param_names)
          best&.first || overloads.first
        end

        # @param [Array<Object>] overloads
        # @param [Integer] arg_count
        # @param [Array<String>] param_names
        # @return [(Object, Integer)?]
        def best_match(overloads, arg_count, param_names)
          candidates = overloads.map { |sig| score_signature(sig, arg_count: arg_count, param_names: param_names) }
          candidates.compact.max_by { |_sig, score| score }
        end

        private

        # @private
        # @param [Object] sig
        # @param [Integer] arg_count
        # @param [Array<String>] param_names
        # @return [(Object, Integer)?]
        def score_signature(sig, arg_count:, param_names:)
          score = 0

          pos_count = sig.positional_types&.length.to_i
          return nil if pos_count > arg_count

          score += score_positional(pos_count, arg_count, sig)
          score += score_params(sig, param_names)
          score += 3 if sig.return_type && !sig.return_type.empty?
          score += 1 if sig.return_type && sig.return_type != 'Object'

          [sig, score]
        end

        # @private
        # @param [Integer] pos_count
        # @param [Integer] arg_count
        # @param [Object] sig
        # @return [Integer]
        def score_positional(pos_count, arg_count, sig)
          if pos_count == arg_count
            10
          elsif pos_count < arg_count && sig.rest_positional
            5
          else
            0
          end
        end

        # @private
        # @param [Object] sig
        # @param [Array<String>] param_names
        # @return [Integer]
        def score_params(sig, param_names)
          if sig.param_types
            (sig.param_types.keys & param_names).length * 2
          else
            0
          end
        end
      end
    end
  end
end
