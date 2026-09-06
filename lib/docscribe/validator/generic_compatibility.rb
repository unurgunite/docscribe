# frozen_string_literal: true

require 'docscribe/types/yard/validator'

module Docscribe
  module Validator
    # Service object answering `generic_compatible?` without hardcoding alias names.
    #
    # Dynamically decides if two type strings are compatible via generics/aliases.
    # Uses hash dispatch to avoid long if/else chains and to allow easy extension.
    module GenericCompatibility
      # Check registry: name => checker method symbol
      CHECKS = {
        generic_base: :generic_base_compatible?,
        short_name: :short_name_compatible?,
        alias_hash: :alias_hash_compatible?,
        tuple_array: :tuple_array_compatible?,
        optional_nil: :optional_nil_compatible?,
        union_containment: :union_containment?,
        optional_suffix: :optional_suffix_compatible?,
        generic_inner_alias: :generic_inner_alias_compatible?,
        fallback_union: :fallback_union_check?
      }.freeze

      class << self
        # Whether two type strings are generic compatible (any checker true).
        #
        # @param [String, nil] yard_type
        # @param [String, nil] expected_type
        # @param [String] fallback_type
        # @return [Boolean]
        def compatible?(yard_type, expected_type, fallback_type: 'Object')
          CHECKS.any? do |name, method_name|
            if name == :fallback_union
              send(method_name, yard_type, expected_type, fallback_type)
            else
              send(method_name, yard_type, expected_type)
            end
          end
        end

        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @param [String] fallback_type Param documentation.
        # @return [Boolean]
        def fallback_union_check?(yard_type, expected_type, fallback_type)
          fallback_union?(yard_type, fallback_type) || fallback_union?(expected_type, fallback_type)
        end

        # Method documentation.
        #
        # @param [String, nil] type_str Param documentation.
        # @param [String] fallback Param documentation.
        # @return [Boolean]
        def fallback_union?(type_str, fallback)
          return false if type_str.nil? || type_str.strip.empty?

          fallback_norm = normalize(fallback)
          parts = type_str.to_s.split(',').map { |part| normalize(part.strip.delete_suffix('?').strip) }
          parts.all? { |part| part == fallback_norm || part.empty? }
        end

        # Whether generic base matches: Hash vs Hash<Symbol,String> or Array vs Array<String>
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def generic_base_compatible?(yard_type, expected_type)
          norm_yard = normalize(yard_type)
          norm_expected = normalize(expected_type)
          return true if norm_yard == norm_expected

          yard_generic = norm_expected !~ /[<\[]/ && (norm_yard.start_with?("#{norm_expected}<") || norm_yard.start_with?("#{norm_expected}["))
          expected_generic = norm_yard !~ /[<\[]/ && (norm_expected.start_with?("#{norm_yard}<") || norm_expected.start_with?("#{norm_yard}["))
          yard_generic || expected_generic
        end

        # Whether short names equal: Docscribe::Config vs Config, Parser::Source::Range vs Range
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def short_name_compatible?(yard_type, expected_type)
          norm_yard = normalize(yard_type)
          norm_expected = normalize(expected_type)
          return false if generic_string?(norm_yard) || generic_string?(norm_expected)

          short_yard = short_name(norm_yard)
          short_expected = short_name(norm_expected)
          short_compatible?(short_yard, short_expected, norm_yard, norm_expected)
        end

        # Method documentation.
        #
        # @param [String] type_str Param documentation.
        # @return [String]
        def short_name(type_str)
          normalize(type_str).split('::').last.to_s.split('<').first.split('[').first.strip
        end

        # Method documentation.
        #
        # @param [String] normalized Param documentation.
        # @return [Boolean]
        def generic_string?(normalized) # rubocop:disable SortedMethodsByCall/Waterfall
          normalized.include?('<') || normalized.include?('[')
        end

        # Method documentation.
        #
        # @param [String] short_yard Param documentation.
        # @param [String] short_expected Param documentation.
        # @param [String] norm_yard Param documentation.
        # @param [String] norm_expected Param documentation.
        # @return [Boolean]
        def short_compatible?(short_yard, short_expected, norm_yard, norm_expected)
          return true if short_yard == short_expected && short_yard != norm_yard && short_expected != norm_expected
          return true if short_yard == norm_expected
          return true if short_expected == norm_yard

          false
        end

        # Whether alias (lowercase after ::) vs Hash/Array/Range etc. is compatible
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def alias_hash_compatible?(yard_type, expected_type)
          norm_yard = normalize(yard_type)
          norm_expected = normalize(expected_type)
          hash_like = %w[Hash Array Range]
          [[norm_yard, norm_expected], [norm_expected, norm_yard]].any? do |alias_type, hash_type|
            base = base_name(hash_type)
            next false unless hash_like.include?(base) || hash_type.start_with?('Hash') || hash_type.start_with?('Array') || hash_type == 'Range'

            short_alias = alias_type.split('::').last.to_s
            short_alias =~ /\A[a-z]/ && alias_type.include?('::')
          end
        end

        # Method documentation.
        #
        # @param [String] type_str Param documentation.
        # @return [String]
        def base_name(type_str)
          normalize(type_str).split('<').first.split('[').first.split('(').first.strip
        end

        # Tuple (String, Integer) vs Array
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def tuple_array_compatible?(yard_type, expected_type)
          norm_yard = normalize(yard_type)
          norm_expected = normalize(expected_type)
          (norm_expected == 'Array' && norm_yard =~ /\A\(.*\)\z/) || (norm_yard == 'Array' && norm_expected =~ /\A\(.*\)\z/)
        end

        # Optional vs nil: String? <-> nil or String, nil <-> nil
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def optional_nil_compatible?(yard_type, expected_type)
          norm_yard = normalize(yard_type)
          norm_expected = normalize(expected_type)
          return true if question_nil_pair?(norm_yard, norm_expected)
          return true if comma_nil_pair?(norm_yard, norm_expected)

          node_nil_pair?(norm_yard, norm_expected)
        end

        # Method documentation.
        #
        # @param [String] norm_yard Param documentation.
        # @param [String] norm_expected Param documentation.
        # @return [Boolean]
        def question_nil_pair?(norm_yard, norm_expected)
          (norm_yard == 'nil' && norm_expected.end_with?('?')) || (norm_expected == 'nil' && norm_yard.end_with?('?'))
        end

        # Method documentation.
        #
        # @param [String] norm_yard Param documentation.
        # @param [String] norm_expected Param documentation.
        # @return [Boolean]
        def comma_nil_pair?(norm_yard, norm_expected)
          (norm_yard.include?(', nil') && norm_expected == 'nil') || (norm_expected.include?(', nil') && norm_yard == 'nil')
        end

        # Method documentation.
        #
        # @param [String] norm_yard Param documentation.
        # @param [String] norm_expected Param documentation.
        # @return [Boolean]
        def node_nil_pair?(norm_yard, norm_expected)
          (norm_yard == 'Parser::AST::Node' && norm_expected == 'nil') || (norm_expected == 'Parser::AST::Node' && norm_yard == 'nil')
        end

        # Union containment: yard in expected union or vice versa
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def union_containment?(yard_type, expected_type)
          return false if yard_type.nil? || expected_type.nil?

          norm_yard = normalize(yard_type)
          expected_type.split(',').any? { |part| normalize(part) == norm_yard } ||
            yard_type.split(',').any? { |part| normalize(part) == normalize(expected_type) }
        end

        # Optional suffix: String vs String?
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def optional_suffix_compatible?(yard_type, expected_type)
          normalize(yard_type).delete_suffix('?') == normalize(expected_type).delete_suffix('?')
        end

        # Generic inner alias: Array<change> vs Array<String> where inner contains alias (lowercase or ::)
        # Method documentation.
        #
        # @param [String, nil] yard_type Param documentation.
        # @param [String, nil] expected_type Param documentation.
        # @return [Boolean]
        def generic_inner_alias_compatible?(yard_type, expected_type)
          norm_yard = normalize(yard_type)
          norm_expected = normalize(expected_type)
          return false unless generic_pair?(norm_yard, norm_expected)

          inner_yard = extract_inner(norm_yard)
          inner_expected = extract_inner(norm_expected)
          return false unless inner_yard && inner_expected

          inner_has_alias?(inner_yard) || inner_has_alias?(inner_expected)
        end

        # Method documentation.
        #
        # @param [String, nil] type_str Param documentation.
        # @return [String]
        def normalize(type_str)
          type_str.to_s.strip.squeeze(' ').gsub('[', '<').gsub(']', '>').gsub(/\buntyped\b/, 'Object')
                  .gsub(/\bFALLBACK_TYPE\b/, 'Object')
        end

        # Method documentation.
        #
        # @param [String] norm_yard Param documentation.
        # @param [String] norm_expected Param documentation.
        # @return [Boolean]
        def generic_pair?(norm_yard, norm_expected)
          norm_yard =~ /\A(?:Array|Hash)[<\[]/ && norm_expected =~ /\A(?:Array|Hash)[<\[]/
        end

        # Method documentation.
        #
        # @param [String] normalized Param documentation.
        # @return [String, nil]
        def extract_inner(normalized)
          normalized[/\A(?:Array|Hash)[<\[](.*)[>\]]\z/, 1]
        end

        # Method documentation.
        #
        # @param [String] inner Param documentation.
        # @return [Boolean]
        def inner_has_alias?(inner)
          inner.split(',').any? { |part| alias_token?(part.strip) }
        end

        # Method documentation.
        #
        # @param [String] token Param documentation.
        # @return [Boolean]
        def alias_token?(token)
          token =~ /\A[a-z]/ || token.include?('::')
        end
      end
    end
  end
end
