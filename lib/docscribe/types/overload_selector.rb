# frozen_string_literal: true

module Docscribe
  module Types
    module OverloadSelector
      class << self
        def select(overloads, arg_count:, param_names: [])
          return nil if overloads.nil? || overloads.empty?
          return overloads.first if overloads.size == 1

          candidates = overloads.map { |sig| score_signature(sig, arg_count: arg_count, param_names: param_names) }
          best = candidates.reject { |_sig, score| score.nil? }
                           .max_by { |_sig, score| score }

          best&.first || overloads.first
        end

        private

        def score_signature(sig, arg_count:, param_names:)
          score = 0

          pos_count = sig.positional_types&.length || 0
          if pos_count == arg_count
            score += 10
          elsif pos_count < arg_count && sig.rest_positional
            score += 5
          elsif pos_count > arg_count
            return nil
          end

          if sig.param_types
            matching_named = (sig.param_types.keys & param_names).length
            score += matching_named * 2
          end

          score += 3 if sig.return_type && !sig.return_type.empty?

          if sig.return_type && sig.return_type != 'Object'
            score += 1
          end

          [sig, score]
        end
      end
    end
  end
end
