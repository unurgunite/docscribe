# frozen_string_literal: true

require_relative 'types'

module Docscribe
  module Types
    # YARD type parser
    module Yard
      class << self
        # @param [Object] string
        # @return [Docscribe::Types::Yard::node?]
        def parse(string)
          return nil if string.nil? || string.strip.empty?

          Parser.new(string).parse
        end
      end

      # Parses YARD type strings into an AST
      class Parser
        # @param [Object] string
        # @return [void]
        def initialize(string)
          @s = string.strip
          @i = 0
        end

        # @return [Docscribe::Types::Yard::node]
        def parse
          skip_space
          node = parse_union
          skip_space
          node
        end

        private

        # @private
        # @return [Docscribe::Types::Yard::node]
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

        # @private
        # @return [Docscribe::Types::Yard::node]
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

        # @private
        # @return [Docscribe::Types::Yard::node]
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

        # @private
        # @return [Docscribe::Types::Yard::node]
        def parse_primary
          skip_space
          case peek
          when '(' then parse_tuple
          when '{' then parse_hash_map
          when '#' then parse_duck_type
          else
            parse_named_type
          end
        end

        # @private
        # @return [Object, Object, Named]
        def parse_named_type
          name = scan_name
          return Literal.new(value: name) if literal?(name)

          skip_space
          if @i < @s.length && @s[@i] == '<'
            parse_generic(Named.new(name: name))
          elsif @i < @s.length && @s[@i] == '{'
            parse_named_hash_map
          else
            Named.new(name: name)
          end
        end

        # @private
        # @param [Object] base
        # @return [Docscribe::Types::Yard::Generic]
        def parse_generic(base)
          @i += 1
          args = parse_generic_args
          @i += 1 if @i < @s.length && @s[@i] == '>'
          Generic.new(base: base.name, args: args)
        end

        # @private
        # @return [Docscribe::Types::Yard::node]
        def parse_generic_arg
          types = [parse_intersection]
          skip_space
          while @i < @s.length && @s[@i] == '|'
            @i += 1
            skip_space
            types << parse_intersection
            skip_space
          end
          types.size == 1 ? types.first : Union.new(types: types)
        end

        # @private
        # @return [Array<Docscribe::Types::Yard::node>]
        def parse_generic_args
          args = [] #: Array[untyped]
          skip_space
          while @i < @s.length && @s[@i] != '>'
            args << parse_generic_arg
            skip_space
            next unless @i < @s.length && @s[@i] == ','

            @i += 1
            skip_space
          end
          args
        end

        # @private
        # @return [Docscribe::Types::Yard::Tuple]
        def parse_tuple
          @i += 1
          types = [] #: Array[untyped]
          while @i < @s.length && @s[@i] != ')'
            types << parse_tuple_element
            @i += 1 and skip_space if @s[@i] == ','
          end
          @i += 1 if @s[@i] == ')'
          Tuple.new(types: types)
        end

        # @private
        # @return [Docscribe::Types::Yard::node]
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

        # @private
        # @return [Docscribe::Types::Yard::HashMap]
        def parse_hash_map
          @i += 1
          key = parse_union
          @i += 2 if @s[@i..(@i + 1)] == '=>'
          value = parse_union
          @i += 1 if @s[@i] == '}'
          HashMap.new(key_type: key, value_type: value)
        end

        # @private
        # @return [Docscribe::Types::Yard::HashMap]
        def parse_named_hash_map
          parse_hash_map
        end

        # @private
        # @return [Docscribe::Types::Yard::Duck]
        def parse_duck_type
          methods = [] #: Array[String]
          while @i < @s.length && @s[@i] == '#'
            @i += 1
            name = scan_name
            methods << name
            skip_space
          end
          Duck.new(method_names: methods)
        end

        # @private
        # @return [String]
        def scan_name
          start = @i
          @i += 1 while @i < @s.length && name_char?(@s[@i])
          @s[start...@i]
        end

        # @private
        # @param [Object] char
        # @return [Boolean]
        def name_char?(char)
          char.match?(/[a-zA-Z0-9_:]/)
        end

        # @private
        # @param [Object] name
        # @return [Boolean]
        def literal?(name)
          %w[void nil self true false].include?(name)
        end

        # @private
        # @return [void]
        def skip_space
          @i += 1 while @i < @s.length && @s[@i].match?(/\s/)
        end

        # @private
        # @return [String?]
        def peek
          @i < @s.length ? @s[@i] : nil
        end
      end
    end
  end
end
