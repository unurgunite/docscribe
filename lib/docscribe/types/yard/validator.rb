# frozen_string_literal: true

require_relative 'parser'

module Docscribe
  module Types
    module Yard
      # Validates YARD type strings for syntax errors.
      #
      # This validator is intentionally lightweight and does not perform
      # semantic type-existence checks (e.g. `Symbol2l` vs `Symbol`).
      # Semantic checks are handled by `Docscribe::Validator::TypeMismatchValidator`
      # which compares a YARD tag against the inferred / RBS type.
      module Validator
        module_function

        # Check if a YARD type string is syntactically valid.
        #
        # Criteria:
        # - non-empty after strip
        # - brackets are balanced (`<>`, `()`, `{}`, `[]`)
        # - no `,,`, `<>`, `,]` artefacts
        # - `Yard::Parser` consumes the entire string (catches `Sym bol` leftover)
        #
        # @param [String] type_str the YARD type string to validate (e.g. "String", "Array<String>", "Sym bol")
        # @return [Boolean] true if valid syntax, false otherwise
        def valid?(type_str)
          syntax_valid?(type_str)
        rescue StandardError
          false
        end

        # Strict syntax validation with balanced brackets and full consumption.
        #
        # @param [String] type_str
        # @return [Boolean]
        def syntax_valid?(type_str)
          return false if type_str.nil? || type_str.strip.empty?
          return false unless balanced_brackets?(type_str)
          return false if type_str.include?(',,') || type_str.include?('<>') || type_str.include?(',]')
          return false unless fully_consumed?(type_str)

          true
        rescue StandardError
          false
        end

        # Check balanced brackets for `<>`, `()`, `{}`, `[]`.
        #
        # @param [String] type_str
        # @return [Boolean]
        def balanced_brackets?(type_str)
          depth_angle = 0
          depth_paren = 0
          depth_brace = 0
          depth_bracket = 0
          type_str.each_char do |ch|
            case ch
            when '<'
              depth_angle += 1
            when '>'
              depth_angle -= 1
              return false if depth_angle.negative?
            when '('
              depth_paren += 1
            when ')'
              depth_paren -= 1
              return false if depth_paren.negative?
            when '{'
              depth_brace += 1
            when '}'
              depth_brace -= 1
              return false if depth_brace.negative?
            when '['
              depth_bracket += 1
            when ']'
              depth_bracket -= 1
              return false if depth_bracket.negative?
            end
          end
          depth_angle.zero? && depth_paren.zero? && depth_brace.zero? && depth_bracket.zero?
        end

        # Whether `Yard::Parser` consumes the entire string.
        #
        # Catches cases like `Sym bol` where parser would return `Sym` and
        # leave ` bol` unconsumed.
        #
        # @param [String] type_str
        # @return [Boolean]
        def fully_consumed?(type_str)
          stripped = type_str.strip
          parser = Parser.new(stripped)
          node = parser.parse
          return false unless node

          idx = parser.instance_variable_get(:@i)
          # `Parser#parse` calls `skip_space` before and after `parse_union`,
          # so `idx` should be at the end if fully consumed.
          idx == stripped.length
        rescue StandardError
          false
        end
      end
    end
  end
end
