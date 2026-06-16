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

        # Dispatch an RBS type object to the appropriate YARD formatter.
        #
        # @note module_function: defines #to_yard (visibility: private)
        # @param [Docscribe::Types::RBS::TypeFormatter::rbs_type, nil] type the RBS type object to convert
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics whether to collapse generics when all inner types are Object
        # @return [String]
        def to_yard(type, collapse_generics: false, collapse_object_generics: false)
          return 'Object' unless type

          handler = to_yard_formatters.find { |klass, _| type.is_a?(klass) }
          return handler.last.call(type, cg: collapse_generics, cog: collapse_object_generics) if handler

          if named_type?(type)
            return format_named(type, # steep:ignore
                                collapse_generics: collapse_generics,
                                collapse_object_generics: collapse_object_generics)
          end

          fallback_string(type)
        end

        # Check if the given type object is a named RBS type (class, singleton, interface, or alias).
        #
        # @note module_function: defines #named_type? (visibility: private)
        # @param [Docscribe::Types::RBS::TypeFormatter::rbs_type] type the RBS type object to check
        # @return [Boolean]
        def named_type?(type)
          named_type_classes.any? { |klass| type.is_a?(klass) }
        end

        # Return or memoize the list of RBS type classes considered named types.
        #
        # @note module_function: defines #named_type_classes (visibility: private)
        # @return [Array<Class>]
        def named_type_classes
          @named_type_classes ||= [
            ::RBS::Types::ClassInstance,
            ::RBS::Types::ClassSingleton,
            ::RBS::Types::Interface,
            ::RBS::Types::Alias
          ].freeze
        end

        # Fallback conversion of an unrecognized RBS type to a cleaned string representation.
        #
        # @note module_function: defines #fallback_string (visibility: private)
        # @param [Docscribe::Types::RBS::TypeFormatter::rbs_type] type the unrecognized RBS type object
        # @return [String]
        def fallback_string(type)
          type.to_s
              .gsub(/\A::/, '')
              .gsub(/\bbool\b/, 'Boolean')
              .gsub(/\buntyped\b/, 'Object')
        end

        # Return or memoize the dispatch hash mapping RBS type classes to formatter lambdas.
        #
        # @note module_function: defines #to_yard_formatters (visibility: private)
        # @return [Hash<Class, Docscribe::Types::RBS::TypeFormatter::formatter_fn>]
        def to_yard_formatters
          @to_yard_formatters ||= formatter_pairs.to_h.freeze
        end

        # Hash of RBS type classes and their YARD formatter lambdas.
        #
        # @note module_function: defines #formatter_pairs (visibility: private)
        # @return [Object]
        def formatter_pairs # steep:ignore # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          @formatter_pairs ||= {
            ::RBS::Types::Bases::Any => ->(_, **) { format_any },
            ::RBS::Types::Bases::Bool => ->(_, **) { format_bool },
            ::RBS::Types::Bases::Void => ->(_, **) { format_void },
            ::RBS::Types::Bases::Nil => ->(_, **) { format_nil },
            ::RBS::Types::Optional => lambda { |t, cg:, cog:|
              format_optional(t, collapse_generics: cg, collapse_object_generics: cog)
            },
            ::RBS::Types::Union => lambda { |t, cg:, cog:|
              format_union(t, collapse_generics: cg, collapse_object_generics: cog)
            },
            ::RBS::Types::Literal => ->(t, **) { format_literal(t.literal) },
            ::RBS::Types::Proc => ->(_, **) { format_proc },
            ::RBS::Types::Tuple => lambda { |t, cg:, cog:|
              format_tuple(t, collapse_generics: cg, collapse_object_generics: cog)
            },
            ::RBS::Types::Bases::Top => ->(_, **) { format_top },
            ::RBS::Types::Bases::Bottom => ->(_, **) { format_bottom },
            ::RBS::Types::Bases::Self => ->(_, **) { format_self },
            ::RBS::Types::Bases::Instance => ->(_, **) { format_instance },
            ::RBS::Types::Bases::Class => ->(_, **) { format_class_type },
            ::RBS::Types::Variable => ->(t, **) { format_variable(t) },
            ::RBS::Types::Record => lambda { |t, cg:, cog:|
              format_record(t, collapse_generics: cg, collapse_object_generics: cog)
            },
            ::RBS::Types::Intersection => ->(t, cg:, cog:) { format_intersection(t, collapse_generics: cg, collapse_object_generics: cog) }
          }.freeze
        end

        # Format RBS `any` type as the YARD-equivalent `Object`.
        #
        # @note module_function: defines #format_any (visibility: private)
        # @return [String]
        def format_any
          'Object'
        end

        # Format RBS `bool` type as the YARD `Boolean`.
        #
        # @note module_function: defines #format_bool (visibility: private)
        # @return [String]
        def format_bool
          'Boolean'
        end

        # Format RBS `void` type as the YARD `void`.
        #
        # @note module_function: defines #format_void (visibility: private)
        # @return [String]
        def format_void
          'void'
        end

        # Format RBS `nil` type as the YARD `nil`.
        #
        # @note module_function: defines #format_nil (visibility: private)
        # @return [String]
        def format_nil
          'nil'
        end

        # Format an RBS Optional type as a YARD optional type with `?` suffix.
        #
        # @note module_function: defines #format_optional (visibility: private)
        # @param [RBS::Types::Optional] type the optional type to format
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics Param documentation.
        # @return [String]
        def format_optional(type, collapse_generics:, collapse_object_generics:)
          "#{to_yard(type.type, collapse_generics: collapse_generics,
                                collapse_object_generics: collapse_object_generics)}?"
        end

        # Map a Ruby literal value to its corresponding YARD type name.
        #
        # @note module_function: defines #format_literal (visibility: private)
        # @param [RBS::Types::Literal] lit a Ruby literal value
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

        # Format RBS Proc type as the YARD `Proc`.
        #
        # @note module_function: defines #format_proc (visibility: private)
        # @return [String]
        def format_proc
          'Proc'
        end

        # Format an RBS Tuple type as a parenthesized list of YARD types.
        #
        # @note module_function: defines #format_tuple (visibility: private)
        # @param [RBS::Types::Tuple] type the tuple type to format
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics Param documentation.
        # @return [String]
        def format_tuple(type, collapse_generics:, collapse_object_generics:)
          "(#{type.types.map do |t|
            to_yard(t, collapse_generics: collapse_generics, collapse_object_generics: collapse_object_generics)
          end.join(', ')})"
        end

        # Format RBS top type as YARD `Object`.
        #
        # @note module_function: defines #format_top (visibility: private)
        # @return [String]
        def format_top
          'Object'
        end

        # Format RBS bottom type as YARD `Object`.
        #
        # @note module_function: defines #format_bottom (visibility: private)
        # @return [String]
        def format_bottom
          'Object'
        end

        # Format RBS self type as YARD `self`.
        #
        # @note module_function: defines #format_self (visibility: private)
        # @return [String]
        def format_self
          'self'
        end

        # Format RBS instance type as YARD `Object`.
        #
        # @note module_function: defines #format_instance (visibility: private)
        # @return [String]
        def format_instance
          'Object'
        end

        # Format RBS class type as YARD `Class`.
        #
        # @note module_function: defines #format_class_type (visibility: private)
        # @return [String]
        def format_class_type
          'Class'
        end

        # Format an RBS type variable as its name string.
        #
        # @note module_function: defines #format_variable (visibility: private)
        # @param [RBS::Types::Variable] type the variable type
        # @return [String]
        def format_variable(type)
          type.name.to_s
        end

        # Format an RBS Record type as a YARD `Hash<Symbol, ValueType>`.
        #
        # @note module_function: defines #format_record (visibility: private)
        # @param [RBS::Types::Record] type the record type
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics Param documentation.
        # @return [String]
        def format_record(type, collapse_generics:, collapse_object_generics:)
          value_types = type.all_fields.values.map do |(ty, _)|
            to_yard(ty, collapse_generics: collapse_generics, collapse_object_generics: collapse_object_generics)
          end.uniq
          "Hash<Symbol, #{value_types.join(', ')}>"
        end

        # Format an RBS Intersection type as `Type & Type` list.
        #
        # @note module_function: defines #format_intersection (visibility: private)
        # @param [RBS::Types::Intersection] type the intersection type
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics Param documentation.
        # @return [String]
        def format_intersection(type, collapse_generics:, collapse_object_generics:)
          type.types.map do |t|
            to_yard(t, collapse_generics: collapse_generics, collapse_object_generics: collapse_object_generics)
          end.join(' & ')
        end

        # Format an RBS Union type as a comma-separated list of YARD types.
        #
        # @note module_function: defines #format_union (visibility: private)
        # @param [RBS::Types::Union] type the union type to format
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics Param documentation.
        # @return [String]
        def format_union(type, collapse_generics:, collapse_object_generics:)
          type.types.map do |t|
            to_yard(t, collapse_generics: collapse_generics, collapse_object_generics: collapse_object_generics)
          end
                    .uniq
                    .join(', ')
        end

        # Format an RBS named type (class, interface, alias) with optional generic arguments.
        #
        # @note module_function: defines #format_named (visibility: private)
        # @param [Docscribe::Types::RBS::TypeFormatter::named_rbs_type] type the unrecognized RBS type object
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics whether to collapse generics when all inner types are Object
        # @return [String]
        def format_named(type, collapse_generics:, collapse_object_generics:)
          name = type.name.to_s.delete_prefix('::')
          args = type.respond_to?(:args) ? type.args : [] #: Array[untyped]

          if args && !args.empty?
            format_generic_args(name, args, collapse_generics: collapse_generics,
                                            collapse_object_generics: collapse_object_generics)
          else
            name
          end
        end

        # Format generic type arguments for a named type.
        #
        # @note module_function: defines #format_generic_args (visibility: private)
        # @param [String] name the type name
        # @param [Array<Object>] args the generic type arguments
        # @param [Boolean] collapse_generics whether to omit generic type arguments
        # @param [Boolean] collapse_object_generics whether to collapse generics when all inner types are Object
        # @return [String]
        def format_generic_args(name, args, collapse_generics:, collapse_object_generics:)
          return name if collapse_generics

          formatted = args.map do |a|
            to_yard(a, collapse_generics: collapse_generics, collapse_object_generics: collapse_object_generics)
          end
          return name if collapse_object_generics && formatted.all? { |s| s == 'Object' }

          "#{name}<#{formatted.join(', ')}>"
        end

        # Convert a Ruby literal value to its YARD type name string.
        #
        # @note module_function: defines #literal_to_yard (visibility: private)
        # @param [Object] lit a Ruby literal value
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
      end
    end
  end
end
