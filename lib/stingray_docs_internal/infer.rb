# frozen_string_literal: true

require 'parser/current'

module StingrayDocsInternal
  module Infer
    class << self
      # Guess param type from default string and param name
      def infer_param_type(name, default_str)
        # splats and kwargs are driven by name shape
        return 'Array' if name.start_with?('*') && !name.start_with?('**')
        return 'Hash'  if name.start_with?('**')
        return 'Proc'  if name.start_with?('&')

        # keyword arg e.g. "verbose:" — default_str might be nil or something
        is_kw = name.end_with?(':')

        node = parse_expr(default_str)
        ty = type_from_literal(node)

        # If kw with no default, still show Object (or Hash for options:)
        if is_kw && default_str.nil?
          return (name == 'options:' ? 'Hash' : 'Object')
        end

        # If param named options and default is {}, call it Hash
        return 'Hash' if name == 'options:' && (default_str == '{}' || ty == 'Hash')

        ty
      end

      # Best-effort parse of a Ruby expression into an AST for classification.
      def parse_expr(src)
        return nil if src.nil? || src.strip.empty?

        buffer = Parser::Source::Buffer.new('(param)')
        buffer.source = src
        Parser::CurrentRuby.new.parse(buffer)
      rescue Parser::SyntaxError
        nil
      end

      # Very conservative return type from method source (def...end)
      # Looks for last expression or explicit return literals.
      def infer_return_type(method_source)
        return 'Object' if method_source.nil? || method_source.strip.empty?

        buffer = Parser::Source::Buffer.new('(method)')
        buffer.source = method_source
        root = Parser::CurrentRuby.new.parse(buffer)
        return 'Object' unless root && %i[def defs].include?(root.type)

        body = root.children.last # method body node
        ty = last_expr_type(body)
        ty || 'Object'
      rescue Parser::SyntaxError
        'Object'
      end

      # Walk down to last expression type in simple bodies; unify returns.
      def last_expr_type(node)
        return nil unless node

        case node.type
        when :begin
          last = node.children.last
          last_expr_type(last)
        when :if
          t = last_expr_type(node.children[1])
          e = last_expr_type(node.children[2])
          unify_types(t, e)
        when :case
          # check whens and else
          branches = node.children[1..].compact.flat_map do |child|
            if child && child.type == :when
              last_expr_type(child.children.last)
            else
              last_expr_type(child)
            end
          end
          branches.compact!
          branches.empty? ? 'Object' : branches.reduce { |a, b| unify_types(a, b) }
        when :return
          type_from_literal(node.children.first)
        else
          type_from_literal(node)
        end
      end

      # Convert a literal AST node to a YARD type string
      def type_from_literal(node)
        return 'Object' unless node

        case node.type
        when :int then 'Integer'
        when :float then 'Float'
        when :str, :dstr then 'String'
        when :sym then 'Symbol'
        when true, false then 'Boolean'
        when :nil then 'nil'
        when :array then 'Array'
        when :hash then 'Hash'
        when :regexp then 'Regexp'
        when :const
          node.children.last.to_s
        when :send
          recv, meth, = node.children
          if meth == :new && recv && recv.type == :const
            recv.children.last.to_s
          else
            'Object'
          end
        else
          'Object'
        end
      end

      def unify_types(a, b)
        a ||= 'Object'
        b ||= 'Object'
        return a if a == b
        # nil-union => Optional
        return "#{a == 'nil' ? b : a}?" if a == 'nil' || b == 'nil'

        'Object'
      end
    end
  end
end
