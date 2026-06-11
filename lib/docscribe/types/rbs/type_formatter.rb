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

        def to_yard_formatters
          @to_yard_formatters ||= {
            ::RBS::Types::Bases::Any => ->(_, **) { format_any },
            ::RBS::Types::Bases::Bool => ->(_, **) { format_bool },
            ::RBS::Types::Bases::Void => ->(_, **) { format_void },
            ::RBS::Types::Bases::Nil => ->(_, **) { format_nil },
            ::RBS::Types::Optional => ->(t, cg:) { format_optional(t, collapse_generics: cg) },
            ::RBS::Types::Union => ->(t, cg:) { format_union(t, collapse_generics: cg) },
            ::RBS::Types::Literal => ->(t, **) { format_literal(t.literal) },
            ::RBS::Types::Proc => ->(_, **) { format_proc }
          }.freeze
        end

        def format_any
          'Object'
        end

        def format_bool
          'Boolean'
        end

        def format_void
          'void'
        end

        def format_nil
          'nil'
        end

        def format_optional(type, collapse_generics:)
          "#{to_yard(type.type, collapse_generics: collapse_generics)}?"
        end

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

        def format_proc
          'Proc'
        end

        def format_union(type, collapse_generics:)
          type.types.map { |t| to_yard(t, collapse_generics: collapse_generics) }
              .uniq
              .join(', ')
        end

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

        def to_yard(type, collapse_generics: false)
          return 'Object' unless type

          handler = to_yard_formatters.find { |klass, _| type.is_a?(klass) }
          return handler.last.call(type, collapse_generics: collapse_generics) if handler

          return format_named(type, collapse_generics: collapse_generics) if named_type?(type)

          fallback_string(type)
        end

        def named_type?(type)
          named_type_classes.any? { |klass| type.is_a?(klass) }
        end

        def named_type_classes
          @named_type_classes ||= [
            ::RBS::Types::ClassInstance,
            ::RBS::Types::ClassSingleton,
            ::RBS::Types::Interface,
            ::RBS::Types::Alias
          ].freeze
        end

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
