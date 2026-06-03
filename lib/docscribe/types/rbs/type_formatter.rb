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

        # Convert one RBS type object into a YARD-ish string.
        #
        # Supported categories include:
        # - base types (`bool`, `nil`, `void`, `untyped`)
        # - optional and union types
        # - named types with optional generic arguments
        # - literal types
        # - Proc types
        #
        # @note module_function: when included, also defines #to_yard (instance visibility: private)
        # @param [Object] type RBS type object
        # @param [Boolean] collapse_generics whether generic arguments should be omitted
        # @return [String]
        def to_yard(type, collapse_generics: false)
          return 'Object' unless type

          # RBS is loaded lazily by the provider; constants below exist only when rbs is available.
          case type
          when ::RBS::Types::Bases::Any
            format_any
          when ::RBS::Types::Bases::Bool
            format_bool
          when ::RBS::Types::Bases::Void
            format_void
          when ::RBS::Types::Bases::Nil
            format_nil
          when ::RBS::Types::Optional
            format_optional(type, collapse_generics: collapse_generics)
          when ::RBS::Types::Union
            format_union(type, collapse_generics: collapse_generics)
          when ::RBS::Types::ClassInstance,
            ::RBS::Types::ClassSingleton,
            ::RBS::Types::Interface,
            ::RBS::Types::Alias
            format_named(type, collapse_generics: collapse_generics)
          when ::RBS::Types::Literal
            format_literal(type.literal)
          when ::RBS::Types::Proc
            format_proc
          else
            fallback_string(type)
          end
        end

        # @note module_function: when included, also defines #format_any (instance visibility: private)
        # @return [String]
        def format_any
          'Object'
        end

        # @note module_function: when included, also defines #format_bool (instance visibility: private)
        # @return [String]
        def format_bool
          'Boolean'
        end

        # @note module_function: when included, also defines #format_void (instance visibility: private)
        # @return [String]
        def format_void
          'void'
        end

        # @note module_function: when included, also defines #format_nil (instance visibility: private)
        # @return [String]
        def format_nil
          'nil'
        end

        # Format an RBS optional type with a trailing `?`.
        #
        # Example:
        # - `String?` => `"String?"`
        #
        # @note module_function: when included, also defines #format_optional (instance visibility: private)
        # @param [::RBS::Types::Optional] type
        # @param [Boolean] collapse_generics
        # @return [String]
        def format_optional(type, collapse_generics:)
          "#{to_yard(type.type, collapse_generics: collapse_generics)}?"
        end

        # Format an RBS literal type into a YARD-ish type name.
        #
        # Examples:
        # - `123` => `"Integer"`
        # - `'hello'` => `"String"`
        # - `true` => `"Boolean"`
        #
        # @note module_function: when included, also defines #format_literal (instance visibility: private)
        # @param [Object] lit literal value
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

        # @note module_function: when included, also defines #format_proc (instance visibility: private)
        # @return [String]
        def format_proc
          'Proc'
        end

        # Format an RBS union type as a comma-separated YARD union.
        #
        # Example:
        # - `String | Integer | nil` => `"String, Integer, nil"`
        #
        # @note module_function: when included, also defines #format_union (instance visibility: private)
        # @param [::RBS::Types::Union] type
        # @param [Boolean] collapse_generics
        # @return [String]
        def format_union(type, collapse_generics:)
          type.types.map { |t| to_yard(t, collapse_generics: collapse_generics) }
              .uniq
              .join(', ')
        end

        # Format a named RBS type, optionally preserving generic arguments.
        #
        # Examples:
        # - `::String` => `"String"`
        # - `::Hash[::Symbol, untyped]` => `"Hash<Symbol, Object>"`
        # - with `collapse_generics: true` => `"Hash"`
        #
        # @note module_function: when included, also defines #format_named (instance visibility: private)
        # @param [Object] type named RBS type
        # @param [Boolean] collapse_generics
        # @return [String]
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

        # Map a literal Ruby value from an RBS literal type into a YARD-ish type name.
        #
        # @note module_function: when included, also defines #literal_to_yard (instance visibility: private)
        # @param [Object] lit literal value
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

        # Fallback string conversion for unsupported or unexpected RBS type objects.
        #
        # Performs a few normalizations for nicer YARD output:
        # - strips leading `::`
        # - converts `bool` to `Boolean`
        # - converts `untyped` to `Object`
        #
        # @note module_function: when included, also defines #fallback_string (instance visibility: private)
        # @param [Object] type
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
