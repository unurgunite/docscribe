# frozen_string_literal: true

require 'parser/ast/processor'

module Docscribe
  module InlineRewriter
    # AST walker that collects "doc insertion targets" for methods.
    #
    # This is where Docscribe models Ruby scoping/visibility semantics, so the doc generator can:
    # - know whether a method is an instance method or class/module method (`#` vs `.`)
    # - add `@private` / `@protected` tags when appropriate
    # - know the container name (`A::B`) to show in `+A::B#foo+`
    #
    # In addition to `private/protected/public` handling, Collector supports `module_function`
    # inside modules:
    # - `module_function` (no args) affects subsequent `def` nodes
    # - `module_function :foo` can retroactively reclassify an already-seen `def foo` as a module method
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
      #
      # Module-function rules modeled (Docscribe choice/UX):
      # - Under `module_function`, Docscribe documents methods as module methods (`Module.foo`) because that is the
      #   callable API most users care about.
      # - We do not attempt to represent the “also a private instance method” aspect of `module_function`, since there
      #   is only one `def` site to attach docs to.
      class VisibilityCtx
        # @return [Symbol] default visibility for instance methods in current context
        attr_accessor :default_instance_vis

        # @return [Symbol] default visibility for class methods in current context
        attr_accessor :default_class_vis

        # @return [Boolean] true when walking within `class << self` for the current container
        attr_accessor :inside_sclass

        # @return [Boolean] true when `module_function` (no args) has been seen; affects subsequent defs
        attr_accessor :module_function_default

        # @return [Hash{Symbol=>Symbol}] explicit visibilities for named instance methods
        attr_reader :explicit_instance

        # @return [Hash{Symbol=>Symbol}] explicit visibilities for named class methods
        attr_reader :explicit_class

        # @return [Hash{Symbol=>true}] methods marked as module functions via `module_function :name`
        attr_reader :module_function_explicit

        # Initialize a fresh visibility context with Ruby defaults (public).
        #
        # @return [VisibilityCtx]
        def initialize
          @default_instance_vis = :public
          @default_class_vis = :public
          @explicit_instance = {}
          @explicit_class = {}
          @inside_sclass = false

          @module_function_default = false
          @module_function_explicit = {} # { name_sym => true }
        end

        # Duplicate context for nested scopes (e.g., entering `class << self`).
        #
        # @return [VisibilityCtx]
        def dup
          c = VisibilityCtx.new
          c.default_instance_vis = default_instance_vis
          c.default_class_vis = default_class_vis
          c.inside_sclass = inside_sclass

          c.module_function_default = module_function_default
          c.module_function_explicit.merge!(module_function_explicit)

          c.explicit_instance.merge!(explicit_instance)
          c.explicit_class.merge!(explicit_class)
          c
        end
      end

      # List of computed insertions for this file.
      #
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
      # This is where:
      # - method nodes (`def`, `defs`) become insertions
      # - `class << self` changes scope/visibility context
      # - `private/protected/public` and `module_function` update context and may reclassify existing insertions
      #
      # @param node [Parser::AST::Node, nil]
      # @param ctx [VisibilityCtx]
      # @return [void]
      def process_stmt(node, ctx)
        return unless node

        case node.type
        when :def
          name, _args, _body = *node

          if module_function_applies?(ctx, name)
            # Under module_function, document `def foo` as `Module.foo`.
            scope = :class
            vis = ctx.explicit_class[name] || ctx.default_class_vis
          elsif ctx.inside_sclass
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
          # Handle module_function (if present), otherwise handle visibility keywords.
          if process_module_function_send(node, ctx)
            # handled
          else
            process_visibility_send(node, ctx)
          end

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

      # True if the node is `self` (used to detect `class << self`).
      #
      # @param node [Parser::AST::Node, nil]
      # @return [Boolean]
      def self_node?(node)
        node && node.type == :self
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

      # Decide whether `module_function` applies to this method name.
      #
      # @param ctx [VisibilityCtx]
      # @param name [Symbol]
      # @return [Boolean]
      def module_function_applies?(ctx, name)
        return false if ctx.inside_sclass

        ctx.module_function_default || ctx.module_function_explicit[name]
      end

      # Process `module_function` calls.
      #
      # Supported forms:
      # - `module_function` (no args): applies to subsequent `def` nodes
      # - `module_function :foo, :bar`: applies immediately and retroactively to already-seen defs
      #
      # We ignore `module_function` inside `class << self` (not a meaningful pattern for our purposes).
      #
      # @param node [Parser::AST::Node] `:send` node
      # @param ctx [VisibilityCtx]
      # @return [Boolean] true if handled, false otherwise
      def process_module_function_send(node, ctx)
        recv, meth, *args = *node
        return false unless recv.nil? && meth == :module_function
        return true if ctx.inside_sclass # ignore inside class << self

        if args.empty?
          # Affects subsequent defs in the current module/class body
          ctx.module_function_default = true
          return true
        end

        # module_function :foo, :bar (can appear after defs — we handle retroactively)
        names = args.map { |arg| extract_name_sym(arg) }.compact
        names.each do |sym|
          ctx.module_function_explicit[sym] = true
          retroactively_promote_module_function(sym)
        end

        true
      end

      # Extract a method name symbol from an AST argument node.
      #
      # Accepts:
      # - `:sym` nodes (`:foo`)
      # - `:str` nodes ("foo")
      #
      # @param arg [Parser::AST::Node]
      # @return [Symbol, nil]
      def extract_name_sym(arg)
        case arg.type
        when :sym then arg.children.first
        when :str then arg.children.first.to_sym
        end
      end

      # Retroactively promote an already-collected `def name_sym` to module/class scope.
      #
      # This is necessary because Ruby allows `module_function :foo` *after* `def foo`.
      #
      # @param name_sym [Symbol]
      # @return [void]
      def retroactively_promote_module_function(name_sym)
        @insertions.reverse_each do |ins|
          next unless ins.container == current_container
          next unless ins.node.type == :def
          next unless ins.node.children[0] == name_sym

          ins.scope = :class
          # If `def foo` was previously treated as a private instance method (because it was under private),
          # but we later promote it to a module/class-style doc (M.foo), then don't mark it @private—keep it user-facing
          ins.visibility = :public if ins.visibility == :private
        end
      end

      # Current container name as a string (e.g. "A::B").
      #
      # @return [String]
      def current_container
        @name_stack.empty? ? 'Object' : @name_stack.join('::')
      end
    end
  end
end
