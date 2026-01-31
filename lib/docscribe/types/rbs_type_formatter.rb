# frozen_string_literal: true

module Docscribe
  module Types
    # Converts RBS type objects into YARD-ish type strings.
    #
    # This is intentionally best-effort formatting. YARD types are not a full type system.
    module RBSTypeFormatter
      module_function

      # Convert an RBS type into a YARD-compatible type string.
      #
      # @param type [Object] an RBS::Types::* object
      # @param collapse_generics [Boolean] if true, `Array<String>` -> `Array`, `Hash<Symbol, Object>` -> `Hash`
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

      # Format union types like `String | Integer | nil`.
      #
      # @param type [RBS::Types::Union]
      # @param collapse_generics [Boolean]
      # @return [String]
      def format_union(type, collapse_generics:)
        # YARD union style: "String, Integer, nil"
        type.types.map { |t| to_yard(t, collapse_generics: collapse_generics) }.uniq.join(', ')
      end

      # Format named types (classes/interfaces/aliases), including generics.
      #
      # @param type [Object]
      # @param collapse_generics [Boolean]
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

      # Convert literal values in RBS (e.g., `1`, `"x"`, `:ok`) to a type name.
      #
      # @param lit [Object]
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

      # Best-effort fallback formatting for unknown/unsupported RBS nodes.
      #
      # @param type [Object]
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
