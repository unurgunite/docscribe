# frozen_string_literal: true

require_relative 'types'

module Docscribe
  module Types
    module Yard
      module Formatter
        class << self
          def to_rbs(node)
            return 'untyped' if node.nil?

            case node
            when Named then format_named(node)
            when Generic then format_generic(node)
            when Union then format_union(node)
            when Intersection then format_intersection(node)
            when Optional then format_optional(node)
            when Tuple then format_tuple(node)
            when HashMap then format_hash_map(node)
            when Literal then format_literal(node)
            else 'untyped'
            end
          end

          private

          def format_named(node)
            case node.name
            when 'Boolean' then 'bool'
            when 'Object' then 'untyped'
            else node.name
            end
          end

          def format_generic(node)
            "#{node.base}[#{node.args.map { |a| to_rbs(a) }.join(', ')}]"
          end

          def format_union(node)
            node.types.map { |t| to_rbs(t) }.join(' | ')
          end

          def format_intersection(node)
            node.types.map { |t| to_rbs(t) }.join(' & ')
          end

          def format_optional(node)
            "#{to_rbs(node.type)}?"
          end

          def format_tuple(node)
            "[#{node.types.map { |t| to_rbs(t) }.join(', ')}]"
          end

          def format_hash_map(node)
            "Hash[#{to_rbs(node.key_type)}, #{to_rbs(node.value_type)}]"
          end

          def format_literal(node)
            case node.value
            when 'void' then 'void'
            when 'nil' then 'nil'
            when 'self' then 'self'
            when 'true', 'false' then 'bool'
            else 'untyped'
            end
          end
        end
      end
    end
  end
end
