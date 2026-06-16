# frozen_string_literal: true

require_relative 'types'

module Docscribe
  module Types
    module Yard
      module_function

      def parse(string)
        return nil if string.nil? || string.strip.empty?

        Parser.new(string).parse
      end

      class Parser
        def initialize(string)
          @s = string.strip
          @i = 0
        end

        def parse
          skip_space
          node = parse_union
          skip_space
          node
        end

        private

        def parse_union
          types = [parse_intersection]
          skip_space
          while @i < @s.length && @s[@i] == ','
            @i += 1
            skip_space
            types << parse_intersection
            skip_space
          end
          types.size == 1 ? types.first : Union.new(types: types)
        end

        def parse_intersection
          types = [parse_optional]
          skip_space
          while @i < @s.length && @s[@i] == '&'
            @i += 1
            skip_space
            types << parse_optional
            skip_space
          end
          types.size == 1 ? types.first : Intersection.new(types: types)
        end

        def parse_optional
          type = parse_primary
          skip_space
          if @i < @s.length && @s[@i] == '?'
            @i += 1
            Optional.new(type: type)
          else
            type
          end
        end

        def parse_primary
          skip_space
          case peek
          when '(' then parse_tuple
          when '{' then parse_hash_map
          when '#' then parse_duck_type
          else
            name = scan_name
            return Literal.new(value: name) if literal?(name)

            named = Named.new(name: name)
            skip_space
            if @i < @s.length && @s[@i] == '<'
              parse_generic(named)
            elsif @i < @s.length && @s[@i] == '{'
              parse_named_hash_map
            else
              named
            end
          end
        end

        def parse_generic(base)
          @i += 1
          args = parse_generic_args
          @i += 1 if @i < @s.length && @s[@i] == '>'
          Generic.new(base: base.name, args: args)
        end

        def parse_generic_args
          args = []
          skip_space
          while @i < @s.length && @s[@i] != '>'
            args << parse_union
            skip_space
            next unless @i < @s.length && @s[@i] == ','

            @i += 1
            skip_space
          end
          args
        end

        def parse_tuple
          @i += 1
          types = []
          skip_space
          while @i < @s.length && @s[@i] != ')'
            types << parse_tuple_element
            skip_space
            break unless @i < @s.length && @s[@i] == ','

            @i += 1
            skip_space
          end
          @i += 1 if @i < @s.length && @s[@i] == ')'
          Tuple.new(types: types)
        end

        def parse_tuple_element
          type = parse_intersection
          skip_space
          if @i < @s.length && @s[@i] == '?'
            @i += 1
            Optional.new(type: type)
          else
            type
          end
        end

        def parse_hash_map
          @i += 1
          skip_space
          key = parse_union
          skip_space
          if @i + 1 < @s.length && @s[@i..(@i + 1)] == '=>'
            @i += 2
            skip_space
          end
          value = parse_union
          skip_space
          @i += 1 if @i < @s.length && @s[@i] == '}'
          HashMap.new(key_type: key, value_type: value)
        end

        def parse_named_hash_map
          @i += 1
          skip_space
          key = parse_union
          skip_space
          if @i + 1 < @s.length && @s[@i..(@i + 1)] == '=>'
            @i += 2
            skip_space
          end
          value = parse_union
          skip_space
          @i += 1 if @i < @s.length && @s[@i] == '}'
          HashMap.new(key_type: key, value_type: value)
        end

        def parse_duck_type
          methods = []
          while @i < @s.length && @s[@i] == '#'
            @i += 1
            name = scan_name
            methods << name
            skip_space
          end
          Duck.new(method_names: methods)
        end

        def scan_name
          start = @i
          @i += 1 while @i < @s.length && name_char?(@s[@i])
          @s[start...@i]
        end

        def name_char?(char)
          char.match?(/[a-zA-Z0-9_:]/)
        end

        def literal?(name)
          %w[void nil self true false].include?(name)
        end

        def skip_space
          @i += 1 while @i < @s.length && @s[@i].match?(/\s/)
        end

        def peek
          @i < @s.length ? @s[@i] : nil
        end
      end
    end
  end
end
