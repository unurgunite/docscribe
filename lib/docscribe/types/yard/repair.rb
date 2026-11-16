# frozen_string_literal: true

require 'set'
require_relative 'validator'

module Docscribe
  module Types
    module Yard
      # Repairs broken YARD type strings back to a valid form.
      #
      # The common failure is a stray space inside a constant name, e.g.
      # `Sym bol` or `Array<Str ing>`. Writers of `@param` tags split long
      # names by accident; the parser then silently truncates at the space
      # (`Sym bol` parses as `Sym`), so the emitted type is both wrong and
      # unvalidated. Squeezing whitespace restores `Symbol`.
      #
      # Repair only claims a fix when the squeezed result is a type we
      # actually know (a core primitive, or a generic built from known
      # primitives). Otherwise it declines, so an unknown identifier is
      # never silently rewritten into a guess.
      module Repair
        module_function

        # Recursively repair a YARD type string.
        #
        # @note module_function: defines #repair (visibility: public)
        # @param [String, nil] type_str broken type string
        # @return [String, nil] repaired type, or nil when no safe repair exists
        def repair(type_str)
          return nil if type_str.nil?

          stripped = type_str.strip
          return stripped if Validator.valid?(stripped) && !stripped.match?(/\s/)
          return nil if stripped.empty?

          known_repair(stripped.gsub(/\s+/, ''))
        end

        # Repair a squeezed type only when every name in it is known.
        #
        # @note module_function: defines #known_repair (visibility: private)
        # @param [String] squeezed type with whitespace removed
        # @return [String, nil]
        def known_repair(squeezed) # rubocop:disable Metrics/CyclomaticComplexity
          return nil unless Validator.valid?(squeezed)
          return squeezed if names_known?([squeezed])

          parts = split_generic(squeezed)
          return nil unless parts

          base, args = parts
          return nil unless names_known?([base])

          inner = args.map { |arg| repair_arg(arg) }
          return nil if inner.any?(&:nil?)

          "#{base}<#{inner.join(',')}>"
        end

        # Repair one generic argument, recursing into nested generics.
        #
        # @note module_function: defines #repair_arg (visibility: private)
        # @param [String] arg squeezed argument
        # @return [String, nil]
        def repair_arg(arg)
          return arg if names_known?([arg])

          nested = split_generic(arg)
          return nil unless nested

          base, args = nested
          return nil unless names_known?([base])

          inner = args.map { |a| repair_arg(a) }
          return nil if inner.any?(&:nil?)

          "#{base}<#{inner.join(',')}>"
        end

        # Split `Base<A, B>` into its base and arguments.
        #
        # @note module_function: defines #split_generic (visibility: private)
        # @param [String] squeezed type string
        # @return [(String, Array<String>), nil] base and args, nil when malformed
        def split_generic(squeezed)
          open_idx = squeezed.index('<')
          return nil unless open_idx && squeezed.end_with?('>')

          base = squeezed[0...open_idx]
          inner = squeezed[(open_idx + 1)..-2]
          return nil if base.empty? || inner.nil? || inner.empty?

          [base, split_args(inner)]
        end

        # Split generic arguments on top-level commas only.
        #
        # @note module_function: defines #split_args (visibility: private)
        # @param [String] inner generic body
        # @return [Array<String>]
        def split_args(inner) # rubocop:disable Metrics/MethodLength
          args = [] #: Array[String]
          depth = 0
          current = +''

          inner.each_char do |ch|
            depth += 1 if ch == '<'
            depth -= 1 if ch == '>'
            if ch == ',' && depth.zero?
              args << current
              current = +''
            else
              current << ch
            end
          end
          args << current
          args
        end

        # Whether a name is a known YARD type.
        #
        # @note module_function: defines #names_known? (visibility: private)
        # @param [Array<String>] names
        # @return [Boolean]
        def names_known?(names)
          names.all? { |name| known_names.include?(name.sub(/\A::/, '')) }
        end

        # Bare names of core primitives, without the leading `::`.
        #
        # @note module_function: defines #known_names (visibility: private)
        # @return [Set<String>]
        def known_names
          @known_names ||= begin
            require_relative '../primitive'
            Docscribe::Types::Primitive.core_primitives.to_set { |p| p.sub(/\A::/, '') }
          end
        end
      end
    end
  end
end
