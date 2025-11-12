# frozen_string_literal: true

require 'parser/current'

module StingrayDocsInternal
  module Infer
    class << self
      # +StingrayDocsInternal::Infer.infer_raises_from_node+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def infer_raises_from_node(node)
        raises = []
        walk = lambda do |n|
          return unless n.is_a?(Parser::AST::Node)

          case n.type
          when :rescue
            n.children.each { |ch| walk.call(ch) }
          when :resbody
            exc_list = n.children[0]
            if exc_list.nil?
              raises << 'StandardError'
            elsif exc_list.type == :array
              exc_list.children.each { |e| (c = const_full_name(e)) && (raises << c) }
            else
              (c = const_full_name(exc_list)) && (raises << c)
            end
            n.children.each { |ch| walk.call(ch) if ch.is_a?(Parser::AST::Node) }
          when :send
            recv, meth, *args = *n
            if recv.nil? && %i[raise fail].include?(meth)
              if args.empty?
                raises << 'StandardError'
              else
                c = const_full_name(args[0])
                raises << (c || 'StandardError')
              end
            end
            n.children.each { |ch| walk.call(ch) if ch.is_a?(Parser::AST::Node) }
          else
            n.children.each { |ch| walk.call(ch) if ch.is_a?(Parser::AST::Node) }
          end
        end
        walk.call(node)
        raises.uniq
      end

      # +StingrayDocsInternal::Infer.const_full_name+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] n Param documentation.
      # @return [Object]
      def const_full_name(n)
        return nil unless n.is_a?(Parser::AST::Node)

        case n.type
        when :const
          scope, name = *n
          scope_name = const_full_name(scope)
          if scope_name && !scope_name.empty?
            "#{scope_name}::#{name}"
          elsif scope_name == '' # leading ::
            "::#{name}"
          else
            name.to_s
          end
        when :cbase
          '' # represents leading :: scope
        end
      end

      # +StingrayDocsInternal::Infer.infer_param_type+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] name Param documentation.
      # @param [Object] default_str Param documentation.
      # @return [Object]
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

      # +StingrayDocsInternal::Infer.parse_expr+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] src Param documentation.
      # @raise [Parser::SyntaxError]
      # @return [Object]
      def parse_expr(src)
        return nil if src.nil? || src.strip.empty?

        buffer = Parser::Source::Buffer.new('(param)')
        buffer.source = src
        Parser::CurrentRuby.new.parse(buffer)
      rescue Parser::SyntaxError
        nil
      end

      # +StingrayDocsInternal::Infer.infer_return_type+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] method_source Param documentation.
      # @raise [Parser::SyntaxError]
      # @return [Object]
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

      # +StingrayDocsInternal::Infer.infer_return_type_from_node+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def infer_return_type_from_node(node)
        body =
          case node.type
          when :def then node.children[2] # [name, args, body]
          when :defs then node.children[3] # [recv, name, args, body]
          end
        return 'Object' unless body

        ty = last_expr_type(body)
        ty || 'Object'
      end

      # +StingrayDocsInternal::Infer.last_expr_type+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
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

      # +StingrayDocsInternal::Infer.type_from_literal+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def type_from_literal(node)
        return 'Object' unless node

        case node.type
        when :int then 'Integer'
        when :float then 'Float'
        when :str, :dstr then 'String'
        when :sym then 'Symbol'
        when :true, :false then 'Boolean' # rubocop:disable Lint/BooleanSymbol
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

      # +StingrayDocsInternal::Infer.unify_types+ -> String
      #
      # Method documentation.
      #
      # @param [Object] a Param documentation.
      # @param [Object] b Param documentation.
      # @return [String]
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
