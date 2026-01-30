# frozen_string_literal: true

module Docscribe
  module Types
    module RBSTypeFormatter
      module_function

      # +Docscribe::Types::RBSTypeFormatter#to_yard+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] type Param documentation.
      # @return [Object]
      def to_yard(type)
        return 'Object' unless type

        case type
        when RBS::Types::Bases::Any
          'Object'
        when RBS::Types::Bases::Bool
          'Boolean'
        when RBS::Types::Bases::Void
          'void'
        when RBS::Types::Bases::Nil
          'nil'

        when RBS::Types::Optional
          "#{to_yard(type.type)}?"

        when RBS::Types::Union
          # YARD union style: "String, Integer, nil"
          type.types.map { |t| to_yard(t) }.uniq.join(', ')

        when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface, RBS::Types::Alias
          name = type.name.to_s.delete_prefix('::')
          args = type.respond_to?(:args) ? type.args : []
          if args && !args.empty?
            "#{name}<#{args.map { |a| to_yard(a) }.join(', ')}>"
          else
            name
          end

        when RBS::Types::Literal
          literal_to_yard(type.literal)

        when RBS::Types::Proc
          'Proc'

        else
          type.to_s
              .gsub(/\A::/, '')
              .gsub(/\bbool\b/, 'Boolean')
              .gsub(/\buntyped\b/, 'Object')
        end
      end

      # +Docscribe::Types::RBSTypeFormatter#literal_to_yard+ -> String
      #
      # Method documentation.
      #
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
        else
          'Object'
        end
      end
    end
  end
end
