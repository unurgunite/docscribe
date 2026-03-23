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

        # Convert one RBS type object into a YARD-ish type string.
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
          when RBS::Types::Bases::Any then 'Object'
          when RBS::Types::Bases::Bool then 'Boolean'
          when RBS::Types::Bases::Void then 'void'
          when RBS::Types::Bases::Nil then 'nil'

          when RBS::Types::Optional
            "#{to_yard(type.type, collapse_generics: collapse_generics)}?"

          when RBS::Types::Union
            format_union(type, collapse_generics: collapse_generics)

          when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface, RBS::Types::Alias
            format_named(type, collapse_generics: collapse_generics)

          when RBS::Types::Literal
            literal_to_yard(type.literal)

          when RBS::Types::Proc
            'Proc'

          else
            fallback_string(type)
          end
        end

        # Format an RBS union type as a comma-separated YARD union.
        #
        # Example:
        # - `String | Integer | nil` => `"String, Integer, nil"`
        #
        # @note module_function: when included, also defines #format_union (instance visibility: private)
        # @param [RBS::Types::Union] type
        # @param [Boolean] collapse_generics
        # @return [String]
        def format_union(type, collapse_generics:)
          type.types.map { |t| to_yard(t, collapse_generics: collapse_generics) }.uniq.join(', ')
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
          else
            'Object'
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
