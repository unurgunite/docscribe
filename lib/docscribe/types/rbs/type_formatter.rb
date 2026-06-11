# frozen_string_literal: true

module Docscribe
  module Types
    module RBS
      # Convert RBS type objects into YARD-ish type strings.
      #
      # This is intentionally best-effort formatting: YARD type syntax is simpler than RBS,
      # so some information is collapsed or approximated.
      module TypeFormatter
        module_function

        # rubocop:disable Metrics/AbcSize, Layout/LineLength
        # Method documentation.
        #
        # @note module_function: when included, also defines #to_yard_formatters (instance visibility: private)
        # @return [Object]
        def to_yard_formatters
          @to_yard_formatters ||= {
            ::RBS::Types::Bases::Any => ->(_, **) { format_any },
            ::RBS::Types::Bases::Bool => ->(_, **) { format_bool },
            ::RBS::Types::Bases::Void => ->(_, **) { format_void },
            ::RBS::Types::Bases::Nil => ->(_, **) { format_nil },
            ::RBS::Types::Optional => ->(t, collapse_generics:) { format_optional(t, collapse_generics: collapse_generics) },
            ::RBS::Types::Union => ->(t, collapse_generics:) { format_union(t, collapse_generics: collapse_generics) },
            ::RBS::Types::Literal => ->(t, **) { format_literal(t.literal) },
            ::RBS::Types::Proc => ->(_, **) { format_proc }
          }.freeze
        end
        # rubocop:enable Metrics/AbcSize, Layout/LineLength

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_any (instance visibility: private)
        # @return [String]
        def format_any
          'Object'
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_bool (instance visibility: private)
        # @return [String]
        def format_bool
          'Boolean'
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_void (instance visibility: private)
        # @return [String]
        def format_void
          'void'
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_nil (instance visibility: private)
        # @return [String]
        def format_nil
          'nil'
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_optional (instance visibility: private)
        # @param [Object] type Param documentation.
        # @param [Object] collapse_generics Param documentation.
        # @return [String]
        def format_optional(type, collapse_generics:)
          "#{to_yard(type.type, collapse_generics: collapse_generics)}?"
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_literal (instance visibility: private)
        # @param [Object] lit Param documentation.
        # @return [String]
        def format_literal(lit)
          case lit
          when Integer then 'Integer'
          when Float   then 'Float'
          when String  then 'String'
          when Symbol  then 'Symbol'
          when TrueClass, FalseClass then 'Boolean'
          when NilClass then 'nil'
          else 'Object'
          end
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_proc (instance visibility: private)
        # @return [String]
        def format_proc
          'Proc'
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_union (instance visibility: private)
        # @param [Object] type Param documentation.
        # @param [Object] collapse_generics Param documentation.
        # @return [Object]
        def format_union(type, collapse_generics:)
          type.types.map { |t| to_yard(t, collapse_generics: collapse_generics) }
              .uniq
              .join(', ')
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #format_named (instance visibility: private)
        # @param [Object] type Param documentation.
        # @param [Object] collapse_generics Param documentation.
        # @return [Object]
        def format_named(type, collapse_generics:)
          name = type.name.to_s.delete_prefix('::')
          args = type.respond_to?(:args) ? type.args : []

          if args && !args.empty?
            return name if collapse_generics

            "#{name}<#{args.map { |a| to_yard(a, collapse_generics: collapse_generics) }.join(', ')}>"
          else
            name
          end
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #literal_to_yard (instance visibility: private)
        # @param [Object] lit Param documentation.
        # @return [String]
        def literal_to_yard(lit)
          case lit
          when Integer then 'Integer'
          when Float   then 'Float'
          when String  then 'String'
          when Symbol  then 'Symbol'
          when TrueClass, FalseClass then 'Boolean'
          when NilClass then 'nil'
          else 'Object'
          end
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #to_yard (instance visibility: private)
        # @param [Object] type Param documentation.
        # @param [Boolean] collapse_generics Param documentation.
        # @return [Object]
        def to_yard(type, collapse_generics: false)
          return 'Object' unless type

          handler = to_yard_formatters.find { |klass, _| type.is_a?(klass) }
          return handler.last.call(type, collapse_generics: collapse_generics) if handler

          return format_named(type, collapse_generics: collapse_generics) if named_type?(type)

          fallback_string(type)
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #named_type? (instance visibility: private)
        # @param [Object] type Param documentation.
        # @return [Boolean]
        def named_type?(type)
          named_type_classes.any? { |klass| type.is_a?(klass) }
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #named_type_classes (instance visibility: private)
        # @return [Object]
        def named_type_classes
          @named_type_classes ||= [
            ::RBS::Types::ClassInstance,
            ::RBS::Types::ClassSingleton,
            ::RBS::Types::Interface,
            ::RBS::Types::Alias
          ].freeze
        end

        # Method documentation.
        #
        # @note module_function: when included, also defines #fallback_string (instance visibility: private)
        # @param [Object] type Param documentation.
        # @return [String]
        def fallback_string(type)
          type.to_s
              .gsub(/\A::/, '')
              .gsub(/\bbool\b/, 'Boolean')
              .gsub(/\buntyped\b/, 'Object')
        end
      end
    end
  end
end
