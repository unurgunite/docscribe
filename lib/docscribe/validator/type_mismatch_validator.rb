# frozen_string_literal: true

require 'docscribe/types/yard/validator'
require 'docscribe/infer/constants'

module Docscribe
  module Validator
    # Compares YARD-documented types against inferred / external types.
    #
    # Lightweight, in-process checks only:
    # - last expression / literal inference (already in `Infer`)
    # - `core_rbs_provider` for stdlib sends (`String#to_i` etc.)
    # - `external_sig` (RBS/Sorbet) when available and `--validate-types` is on
    #
    # Heavy inter-procedural `send("foo")` graph is out of scope for this MVP.
    # When `expected` is `Object` (fallback) we silence to avoid false positives.
    class TypeMismatchValidator
      # @!attribute [rw] type
      #   @return [Symbol] `:type_mismatch_return`, `:type_mismatch_param`, `:invalid_syntax`
      # @!attribute [rw] yard_type
      #   @return [String, nil] type written in YARD
      # @!attribute [rw] expected_type
      #   @return [String] type inferred or from RBS/Sorbet
      # @!attribute [rw] message
      #   @return [String] human-readable
      Result = Struct.new(:type, :yard_type, :expected_type, :message, keyword_init: true)

      # @param [String] fallback_type value of `inference.fallback_type` (default `Object`)
      def initialize(fallback_type: Infer::FALLBACK_TYPE)
        @fallback_type = fallback_type.to_s
      end

      # Whether a documented param type mismatches the expected one.
      #
      # @param [String, nil] yard_type type from `@param [...]`
      # @param [String, nil] expected_type type from `external_sig` or `Infer`
      # @return [Boolean]
      def mismatched_param?(yard_type, expected_type)
        mismatched_return?(yard_type, expected_type)
      end

      # Whether a documented return type mismatches the expected one.
      #
      # @param [String, nil] yard_type type from `@return [...]`
      # @param [String, nil] expected_type inferred or external `normal_type`
      # @return [Boolean]
      def mismatched_return?(yard_type, expected_type)
        return false if yard_type.nil? || yard_type.strip.empty?
        return false if expected_type.nil? || expected_type.strip.empty?
        return false if normalize(expected_type) == @fallback_type # uncertain -> silence

        normalize(yard_type) != normalize(expected_type)
      end

      # Whether a YARD type string has invalid syntax (e.g. `Sym bol` leftover).
      #
      # @param [String, nil] yard_type
      # @return [Boolean]
      def invalid_syntax?(yard_type) # rubocop:disable SortedMethodsByCall/Waterfall
        return false if yard_type.nil? || yard_type.strip.empty?

        !Types::Yard::Validator.valid?(yard_type)
      end

      # Build a Result for a return mismatch, or nil if no mismatch.
      #
      # @param [String, nil] yard_type
      # @param [String, nil] expected_type
      # @return [Result, nil]
      def check_return(yard_type, expected_type)
        return invalid_return_result(yard_type, expected_type) if invalid_syntax?(yard_type)
        return unless mismatched_return?(yard_type, expected_type)

        mismatch_return_result(yard_type, expected_type)
      end

      # Build a Result for a param mismatch, or nil if no mismatch.
      #
      # @param [String] param_name
      # @param [String, nil] yard_type
      # @param [String, nil] expected_type
      # @return [Result, nil]
      def check_param(param_name, yard_type, expected_type)
        return invalid_param_result(param_name, yard_type, expected_type) if invalid_syntax?(yard_type)
        return unless mismatched_param?(yard_type, expected_type)

        mismatch_param_result(param_name, yard_type, expected_type)
      end

      # @private
      # @param [String, nil] yard_type
      # @param [String, nil] expected_type
      # @return [Result]
      def invalid_return_result(yard_type, expected_type)
        Result.new(
          type: :invalid_syntax,
          yard_type: yard_type,
          expected_type: expected_type,
          message: "invalid YARD type [#{yard_type}]#{" expected [#{expected_type}]" if expected_type && expected_type != @fallback_type}"
        )
      end

      # @private
      # @param [String, nil] yard_type
      # @param [String, nil] expected_type
      # @return [Result]
      def mismatch_return_result(yard_type, expected_type)
        Result.new(
          type: :type_mismatch_return,
          yard_type: yard_type,
          expected_type: expected_type,
          message: "updated @return from #{yard_type} to #{expected_type}"
        )
      end

      # @private
      # @param [String] param_name
      # @param [String, nil] yard_type
      # @param [String, nil] expected_type
      # @return [Result]
      def invalid_param_result(param_name, yard_type, expected_type)
        Result.new(
          type: :invalid_syntax,
          yard_type: yard_type,
          expected_type: expected_type,
          message: "invalid YARD type [#{yard_type}] for @param #{param_name}#{" expected [#{expected_type}]" if expected_type && expected_type != @fallback_type}"
        )
      end

      # @private
      # @param [String] param_name
      # @param [String, nil] yard_type
      # @param [String, nil] expected_type
      # @return [Result]
      def mismatch_param_result(param_name, yard_type, expected_type)
        Result.new(
          type: :type_mismatch_param,
          yard_type: yard_type,
          expected_type: expected_type,
          message: "updated @param #{param_name} from #{yard_type} to #{expected_type}"
        )
      end

      private

      # Normalize a type string for comparison (strip, squeeze spaces).
      #
      # @param [String] type_str
      # @return [String]
      def normalize(type_str)
        type_str.to_s.strip.squeeze(' ')
      end
    end
  end
end
