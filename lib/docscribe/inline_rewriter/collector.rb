# frozen_string_literal: true

require 'parser/ast/processor'

module Docscribe
  module InlineRewriter
    # AST walker that collects “doc insertion targets” for methods.
    #
    # This is where Docscribe models Ruby scoping/visibility semantics, so the doc generator can:
    # - know whether a method is an instance method or class method (`#` vs `.`)
    # - add `@private` / `@protected` tags when appropriate
    # - know the container name (`A::B`) to show in `+A::B#foo+`
    class Collector < Parser::AST::Processor
      # One method that Docscribe intends to document.
      #
      # @!attribute node
      #   @return [Parser::AST::Node] the `:def` or `:defs` node
      # @!attribute scope
      #   @return [Symbol] :instance or :class
      # @!attribute visibility
      #   @return [Symbol] :public, :protected, or :private
      # @!attribute container
      #   @return [String] container name, e.g. "MyModule::MyClass"
      Insertion = Struct.new(:node, :scope, :visibility, :container)

      # Tracks Ruby visibility state while walking a class/module body.
      #
      # Ruby rules modeled:
      # - `private/protected/public` without args sets the default visibility for subsequent *instance* methods.
      # - Inside `class << self`, the same keywords set default visibility for subsequent *class* methods.
      # - `private :foo` (with args) sets visibility only for named methods.
      class VisibilityCtx
        attr_accessor :default_instance_vis, :default_class_vis, :inside_sclass
        attr_reader :explicit_instance, :explicit_class

        # Initialize a fresh visibility context with Ruby defaults (public).
        #
        # @return [VisibilityCtx]
        def initialize
          @default_instance_vis = :public
          @default_class_vis = :public
          @explicit_instance = {}
          @explicit_class = {}
          @inside_sclass = false
        end

        # Duplicate context for nested scopes (e.g., entering `class << self`).
        #
        # @return [VisibilityCtx]
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

      # @return [Array<Insertion>]
      attr_reader :insertions

      # @param buffer [Parser::Source::Buffer]
      def initialize(buffer)
        super()
        @buffer = buffer
        @insertions = []
        @name_stack = []
      end

      # Enter a class node and process its body with a fresh visibility context.
      #
      # @param node [Parser::AST::Node] `:class` node
      # @return [Parser::AST::Node]
      def on_class(node)
        cname_node, _super_node, body = *node
        @name_stack.push(const_name(cname_node))
        ctx = VisibilityCtx.new
        process_body(body, ctx)
        @name_stack.pop
        node
      end

      # Enter a module node and process its body with a fresh visibility context.
      #
      # @param node [Parser::AST::Node] `:module` node
      # @return [Parser::AST::Node]
      def on_module(node)
        cname_node, body = *node
        @name_stack.push(const_name(cname_node))
        ctx = VisibilityCtx.new
        process_body(body, ctx)
        @name_stack.pop
        node
      end

      private

      # Process one statement in a class/module body, updating visibility context and/or collecting insertions.
      #
      # @param node [Parser::AST::Node, nil]
      # @param ctx [VisibilityCtx]
      # @return [void]
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
          # `class << self` — affects default visibility for singleton methods and changes scope.
          recv, body = *node
          inner_ctx = ctx.dup
          inner_ctx.inside_sclass = self_node?(recv)
          inner_ctx.default_class_vis = :public
          process_body(body, inner_ctx)

        when :send
          # visibility modifiers: private/protected/public
          process_visibility_send(node, ctx)

        else
          process(node)
        end
      end

      # Handle `private`, `protected`, `public` statements.
      #
      # Supported forms:
      # - `private` (no args) → sets default visibility for subsequent defs
      # - `private :foo, :bar` → sets explicit visibility for named methods
      #
      # @param node [Parser::AST::Node] `:send` node
      # @param ctx [VisibilityCtx]
      # @return [void]
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

      # Extract a symbol method name from `:sym` or `:str` arguments to visibility calls.
      #
      # @param arg [Parser::AST::Node]
      # @return [Symbol, nil]
      def extract_name_sym(arg)
        case arg.type
        when :sym then arg.children.first
        when :str then arg.children.first.to_sym
        end
      end

      # True if the node is `self` (used to detect `class << self`).
      #
      # @param node [Parser::AST::Node, nil]
      # @return [Boolean]
      def self_node?(node)
        node && node.type == :self
      end

      # Current container name as a string (e.g. "A::B").
      #
      # @return [String]
      def current_container
        @name_stack.empty? ? 'Object' : @name_stack.join('::')
      end

      # Convert a constant AST node into a string name.
      #
      # Handles nested constants and leading `::`.
      #
      # @param node [Parser::AST::Node, nil]
      # @return [String]
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

      # Process a class/module body node.
      #
      # Ruby bodies are either:
      # - `:begin` with multiple statements, or
      # - a single node (one statement)
      #
      # @param body [Parser::AST::Node, nil]
      # @param ctx [VisibilityCtx]
      # @return [void]
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
