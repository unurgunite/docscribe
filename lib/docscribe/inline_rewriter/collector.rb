# frozen_string_literal: true

require 'parser/ast/processor'

module Docscribe
  module InlineRewriter
    # Walks the AST and records where docs should be inserted.
    #
    # Collector emits a list of `Insertion` objects. Each insertion includes:
    # - the method node (`def` or `defs`)
    # - scope (`:instance` or `:class`)
    # - visibility (`:public`, `:protected`, `:private`)
    # - container string (e.g. "MyModule::MyClass")
    #
    # This is how Docscribe avoids guessing Ruby visibility: it models the effects of
    # `private/protected/public` in class/module bodies and within `class << self`.
    class Collector < Parser::AST::Processor
      # One planned doc insertion.
      Insertion = Struct.new(:node, :scope, :visibility, :container)

      # Tracks current visibility state while walking a class/module body.
      class VisibilityCtx
        attr_accessor :default_instance_vis, :default_class_vis, :inside_sclass
        attr_reader :explicit_instance, :explicit_class

        def initialize
          @default_instance_vis = :public
          @default_class_vis = :public
          @explicit_instance = {}
          @explicit_class = {}
          @inside_sclass = false
        end

        def dup
          c = VisibilityCtx.new
          c.default_instance_vis = default_instance_vis
          c.default_class_vis = default_class_vis
          c.inside_sclass = inside_sclass
          c.explicit_instance.merge!(explicit_instance)
          c.explicit_class.merge!(explicit_class)
          c
        end
      end

      attr_reader :insertions

      # @param buffer [Parser::Source::Buffer]
      def initialize(buffer)
        super()
        @buffer = buffer
        @insertions = []
        @name_stack = []
      end

      def on_class(node)
        cname_node, _super_node, body = *node
        @name_stack.push(const_name(cname_node))
        ctx = VisibilityCtx.new
        process_body(body, ctx)
        @name_stack.pop
        node
      end

      def on_module(node)
        cname_node, body = *node
        @name_stack.push(const_name(cname_node))
        ctx = VisibilityCtx.new
        process_body(body, ctx)
        @name_stack.pop
        node
      end

      private

      def process_stmt(node, ctx)
        return unless node

        case node.type
        when :def
          name, _args, _body = *node

          if ctx.inside_sclass
            vis = ctx.explicit_class[name] || ctx.default_class_vis
            scope = :class
          else
            vis = ctx.explicit_instance[name] || ctx.default_instance_vis
            scope = :instance
          end

          @insertions << Insertion.new(node, scope, vis, current_container)

        when :defs
          _recv, name, _args, _body = *node
          vis = ctx.explicit_class[name] || ctx.default_class_vis
          @insertions << Insertion.new(node, :class, vis, current_container)

        when :sclass
          recv, body = *node
          inner_ctx = ctx.dup
          inner_ctx.inside_sclass = self_node?(recv)
          inner_ctx.default_class_vis = :public
          process_body(body, inner_ctx)

        when :send
          process_visibility_send(node, ctx)

        else
          process(node)
        end
      end

      def process_visibility_send(node, ctx)
        recv, meth, *args = *node
        return unless recv.nil? && %i[private protected public].include?(meth)

        if args.empty?
          if ctx.inside_sclass
            ctx.default_class_vis = meth
          else
            ctx.default_instance_vis = meth
          end
        else
          args.each do |arg|
            sym = extract_name_sym(arg)
            next unless sym

            if ctx.inside_sclass
              ctx.explicit_class[sym] = meth
            else
              ctx.explicit_instance[sym] = meth
            end
          end
        end
      end

      def extract_name_sym(arg)
        case arg.type
        when :sym then arg.children.first
        when :str then arg.children.first.to_sym
        end
      end

      def self_node?(node)
        node && node.type == :self
      end

      def current_container
        @name_stack.empty? ? 'Object' : @name_stack.join('::')
      end

      def const_name(node)
        return 'Object' unless node

        case node.type
        when :const
          scope, name = *node
          scope_name = scope ? const_name(scope) : nil
          [scope_name, name].compact.join('::')
        when :cbase
          ''
        else
          node.loc.expression.source
        end
      end

      def process_body(body, ctx)
        return unless body

        if body.type == :begin
          body.children.each { |child| process_stmt(child, ctx) }
        else
          process_stmt(body, ctx)
        end
      end
    end
  end
end
