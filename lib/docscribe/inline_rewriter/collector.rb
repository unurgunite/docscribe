# frozen_string_literal: true

require 'parser/ast/processor'

module Docscribe
  module InlineRewriter
    # AST walker that collects documentation insertion targets.
    #
    # This is where Docscribe models Ruby scoping and visibility semantics so the
    # doc generator can:
    # - know whether a method is an instance method or class/module method (`#` vs `.`)
    # - add `@private` / `@protected` tags when appropriate
    # - know the container name (`A::B`) to show in `+A::B#foo+`
    #
    # In addition to `private` / `protected` / `public` handling, Collector
    # supports:
    # - `module_function` inside modules
    # - `extend self` inside modules
    # - receiver-based containers (`def Foo.bar`, `class << Foo`)
    # - Sorbet-aware anchoring for methods with leading `sig` declarations
    class Collector < Parser::AST::Processor
      PROCESS_STMT_HANDLERS = {
        def: :process_def_stmt,
        defs: :process_defs_stmt,
        sclass: :process_sclass_stmt,
        send: :process_send_stmt
      }.freeze

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
      # @!attribute module_function
      #   @return [Boolean, nil] true if documented under module_function semantics
      # @!attribute included_instance_visibility
      #   @return [Symbol, nil] included instance visibility under module_function
      # @!attribute anchor_node
      #   @return [Parser::AST::Node] first leading Sorbet `sig` if present, else the method node
      Insertion = Struct.new(:node, :scope, :visibility, :container, :module_function, :included_instance_visibility,
                             :anchor_node)

      # One attribute macro call that Docscribe intends to document.
      #
      # This corresponds to an `attr_reader`, `attr_writer`, or `attr_accessor` call in Ruby source.
      #
      # @!attribute node
      #   @return [Parser::AST::Node] the `:send` node (e.g. `attr_reader :name`)
      # @!attribute scope
      #   @return [Symbol] :instance or :class (class when inside `class << self`)
      # @!attribute visibility
      #   @return [Symbol] :public, :protected, or :private
      # @!attribute container
      #   @return [String] container name, e.g. "MyModule::MyClass"
      # @!attribute access
      #   @return [Symbol] :r, :w, or :rw (reader/writer/accessor)
      # @!attribute names
      #   @return [Array<Symbol>] attribute names
      AttrInsertion = Struct.new(:node, :scope, :visibility, :container, :access, :names)

      # Tracks visibility and container state while walking a class/module body.
      #
      # The context carries enough Ruby state to support:
      # - lexical visibility changes
      # - `class << self`
      # - `module_function`
      # - `extend self`
      # - retroactive visibility updates
      class VisibilityCtx
        # @!attribute [rw] default_instance_vis
        #   @return [Object]
        #   @param value [Object]
        attr_accessor :default_instance_vis

        # @!attribute [rw] default_class_vis
        #   @return [Object]
        #   @param value [Object]
        attr_accessor :default_class_vis

        # @!attribute [rw] inside_sclass
        #   @return [Object]
        #   @param value [Object]
        attr_accessor :inside_sclass

        # @!attribute [rw] module_function_default
        #   @return [Object]
        #   @param value [Object]
        attr_accessor :module_function_default

        # @!attribute [rw] container_override
        #   @return [Object]
        #   @param value [Object]
        attr_accessor :container_override

        # @!attribute [r] explicit_instance
        #   @return [Object]
        attr_reader :explicit_instance

        # @!attribute [r] explicit_class
        #   @return [Object]
        attr_reader :explicit_class

        # @!attribute [r] module_function_explicit
        #   @return [Object]
        attr_reader :module_function_explicit

        # @!attribute [rw] container_is_module
        #   @return [Object]
        #   @param value [Object]
        attr_accessor :container_is_module

        # @!attribute [rw] extend_self
        #   @return [Object]
        #   @param value [Object]
        attr_accessor :extend_self

        # Create a fresh visibility context with Ruby-like defaults.
        #
        # @return [void]
        def initialize
          @default_instance_vis = :public
          @default_class_vis = :public
          @explicit_instance = {}
          @explicit_class = {}
          @inside_sclass = false
          @module_function_default = false
          @module_function_explicit = {}
          @container_override = nil
          @container_is_module = false
          @extend_self = false
        end

        # Duplicate the context so nested bodies can mutate state independently.
        #
        # @return [VisibilityCtx]
        def dup
          VisibilityCtx.new.tap do |ctx|
            copy_visibility_state(ctx)
            copy_module_function_state(ctx)
            copy_container_state(ctx)
          end
        end

        private

        # Method documentation.
        #
        # @private
        # @param [Object] ctx Param documentation.
        # @return [Object]
        def copy_visibility_state(ctx)
          ctx.default_instance_vis = default_instance_vis
          ctx.default_class_vis = default_class_vis
          ctx.inside_sclass = inside_sclass

          ctx.explicit_instance.merge!(explicit_instance)
          ctx.explicit_class.merge!(explicit_class)
        end

        # Method documentation.
        #
        # @private
        # @param [Object] ctx Param documentation.
        # @return [Object]
        def copy_module_function_state(ctx)
          ctx.module_function_default = module_function_default
          ctx.module_function_explicit.merge!(module_function_explicit)
        end

        # Method documentation.
        #
        # @private
        # @param [Object] ctx Param documentation.
        # @return [Object]
        def copy_container_state(ctx)
          ctx.container_override = container_override
          ctx.container_is_module = container_is_module
          ctx.extend_self = extend_self
        end
      end

      # @!attribute [r] insertions
      #  @return [Array<Insertion>]
      attr_reader :insertions

      # @!attribute [r] attr_insertions
      #   @return [Array<AttrInsertion>]
      attr_reader :attr_insertions

      # Create a collector for the given source buffer.
      #
      # @param [Parser::Source::Buffer] buffer source buffer for anchor location lookups
      # @return [Collector]
      def initialize(buffer)
        super()
        @buffer = buffer
        @insertions = []
        @attr_insertions = []
        @name_stack = []

        # Track module-level state across reopened modules within the same file pass.
        # Example:
        #   module M; extend self; end
        #   module M; def foo; end; end  # => should still document foo as M.foo
        #
        # @type [Hash{String=>Hash}]
        @module_states = {} # { "M" => { extend_self: true } }
      end

      # Enter a class body and collect documentation targets from its contents.
      #
      # @param [Parser::AST::Node] node
      # @return [Parser::AST::Node]
      def on_class(node)
        cname_node, super_node, body = *node
        @name_stack.push(const_name(cname_node))

        ctx = VisibilityCtx.new
        ctx.container_is_module = false

        process_struct_class(node, super_node)
        process_body(body, ctx)

        @name_stack.pop
        node
      end

      # Enter a module body and collect documentation targets from its contents.
      #
      # This also carries `extend self` state across reopened modules in the same
      # file.
      #
      # @param [Parser::AST::Node] node
      # @return [Parser::AST::Node]
      def on_module(node)
        cname_node, body = *node
        @name_stack.push(const_name(cname_node))

        container = current_container

        ctx = VisibilityCtx.new
        ctx.container_is_module = true
        ctx.extend_self = !!@module_states.dig(container, :extend_self)

        process_body(body, ctx)

        # If `extend self` is active for this module, document all instance defs as module methods (M.foo).
        persist_extend_self_state(ctx, container)

        @name_stack.pop
        node
      end

      # Process a constant assignment (e.g. `FOO = ...` or `Foo::BAR = ...`).
      #
      # If the value is a `Struct.new` call, extracts attribute insertions first.
      # Then continues processing child nodes.
      #
      # @param [Parser::AST::Node] node a `:casgn` node
      # @return [Parser::AST::Node] the original node
      def on_casgn(node)
        return node if process_struct_casgn?(node)

        node.children.each do |child|
          process(child) if child.is_a?(Parser::AST::Node)
        end

        node
      end

      # Enter a top-level method definition and collect it as a documentation target.
      #
      # Top-level methods implicitly belong to +Object+. This handler ensures
      # that +def foo+ declared outside of any class or module is still picked
      # up by the collector.
      #
      # @param [Parser::AST::Node] node
      # @return [Parser::AST::Node]
      def on_def(node)
        return node unless @name_stack.empty?

        ctx = VisibilityCtx.new
        ctx.container_is_module = false
        process_stmt(node, ctx)
        node
      end

      # Enter a top-level singleton method definition and collect it as a documentation target.
      #
      # Handles the case of +def self.foo+ declared at the top level, outside
      # of any class or module body.
      #
      # @param [Parser::AST::Node] node
      # @return [Parser::AST::Node]
      def on_defs(node)
        return node unless @name_stack.empty?

        ctx = VisibilityCtx.new
        ctx.container_is_module = false
        process_stmt(node, ctx)
        node
      end

      private

      # Process a `:def` node for documentation insertion.
      #
      # @private
      # @param [Parser::AST::Node] node
      # @param [VisibilityCtx] ctx
      # @param [Parser::AST::Node, nil] pending_sig_anchor
      # @return [void]
      def process_def_stmt(node, ctx, pending_sig_anchor:)
        name, = *node
        anchor_node = pending_sig_anchor || node

        return process_module_function_def(node, name, ctx, anchor_node) if module_function_applies?(ctx, name)
        return process_extend_self_def(node, name, ctx, anchor_node) if extend_self_applies?(ctx)

        scope, visibility = def_scope_visibility(ctx, name)

        @insertions << Insertion.new(node, scope, visibility, container_for(ctx), nil, nil, anchor_node)
      end

      # Method documentation.
      #
      # @private
      # @param [Parser::AST::Node] node
      # @param [VisibilityCtx] ctx
      # @param [Parser::AST::Node, nil] pending_sig_anchor
      # @return [void]
      def process_defs_stmt(node, ctx, pending_sig_anchor:)
        recv, name, _args, _body = *node
        vis = ctx.explicit_class[name] || ctx.default_class_vis

        container =
          if const_receiver?(recv)
            const_name(recv)
          else
            container_for(ctx)
          end

        @insertions << Insertion.new(node, :class, vis, container, nil, nil, pending_sig_anchor || node)
      end

      # Process a `:sclass` node for documentation insertion.
      #
      # @private
      # @param [Parser::AST::Node] node
      # @param [VisibilityCtx] ctx
      # @return [void]
      def process_sclass_stmt(node, ctx)
        # `class << self` — affects default visibility for singleton methods and changes scope.
        recv, body = *node
        inner_ctx = ctx.dup

        configure_sclass_context(inner_ctx, recv)

        process_body(body, inner_ctx)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @param [Object] recv Param documentation.
      # @return [Object]
      def configure_sclass_context(ctx, recv)
        ctx.inside_sclass = sclass_receiver?(recv)
        ctx.container_override = sclass_container_override(recv)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] recv Param documentation.
      # @return [Object]
      def sclass_receiver?(recv)
        self_node?(recv) || const_receiver?(recv)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] recv Param documentation.
      # @return [nil]
      def sclass_container_override(recv)
        return nil if self_node?(recv)
        return const_name(recv) if const_receiver?(recv)

        nil
      end

      # Process a `:send` node for documentation insertion.
      #
      # @private
      # @param [Parser::AST::Node] node
      # @param [VisibilityCtx] ctx
      # @param [Parser::AST::Node, nil] pending_sig_anchor
      # @return [void]
      def process_send_stmt(node, ctx, pending_sig_anchor:)
        if process_attr_send?(node, ctx)
          # handled
        elsif process_extend_self_send?(node, ctx)
          # handled
        elsif process_module_function_send?(node, ctx)
          # handled
        elsif process_class_method_visibility_send?(node, ctx)
          # handled
        else
          process_visibility_send(node, ctx, pending_sig_anchor: pending_sig_anchor)
        end
      end

      # Check if a class inherits from Struct.new and extract attribute insertions.
      #
      # @private
      # @param [Parser::AST::Node] node the class declaration node
      # @param [Parser::AST::Node, nil] super_node the superclass expression
      # @return [void]
      def process_struct_class(node, super_node)
        return unless struct_new_node?(super_node)

        names = extract_struct_member_names(super_node)
        return if names.empty?

        @attr_insertions << AttrInsertion.new(node, :instance, :public, current_container, :rw, names)
      end

      # Detect `attr_reader` / `attr_writer` / `attr_accessor` calls and record attribute insertions.
      #
      # @private
      # @param [Parser::AST::Node] node a `:send` node
      # @param [VisibilityCtx] ctx current visibility context
      # @return [Boolean] true if the node was an attr_* call
      def process_attr_send?(node, ctx)
        recv, meth, *args = *node

        return false unless attr_send?(recv, meth)

        names = args.map { |arg| extract_name_sym(arg) }.compact
        return true if names.empty?

        scope, visibility = attr_scope_visibility(ctx)
        access = attr_access_type(meth)

        @attr_insertions << AttrInsertion.new(node, scope, visibility, container_for(ctx), access, names)

        true
      end

      # Detect `extend self` calls inside a module and persist the state.
      #
      # @private
      # @param [Parser::AST::Node] node a `:send` node
      # @param [VisibilityCtx] ctx current visibility context
      # @return [Boolean] true if `extend self` was detected
      def process_extend_self_send?(node, ctx)
        recv, meth, *args = *node

        return false unless extend_self_send?(ctx, recv, meth, args)

        persist_extend_self(ctx)

        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @return [Object]
      def persist_extend_self(ctx)
        ctx.extend_self = true

        container = container_for(ctx)
        (@module_states[container] ||= {})[:extend_self] = true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @param [Object] recv Param documentation.
      # @param [Object] meth Param documentation.
      # @param [Object] args Param documentation.
      # @return [Object]
      def extend_self_send?(ctx, recv, meth, args)
        ctx.container_is_module &&
          recv.nil? &&
          meth == :extend &&
          !ctx.inside_sclass &&
          args.any? { |arg| self_node?(arg) }
      end

      # Check if a node is a constant or `::` (cbase) receiver.
      #
      # @private
      # @param [Parser::AST::Node, nil] node an AST node
      # @return [Boolean]
      def const_receiver?(node)
        return false unless node.is_a?(Parser::AST::Node)

        %i[const cbase].include?(node.type)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] recv Param documentation.
      # @param [Object] meth Param documentation.
      # @return [Object]
      def attr_send?(recv, meth)
        recv.nil? && %i[attr_reader attr_writer attr_accessor].include?(meth)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @return [Array]
      def attr_scope_visibility(ctx)
        if ctx.inside_sclass
          [:class, ctx.default_class_vis]
        else
          [:instance, ctx.default_instance_vis]
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] meth Param documentation.
      # @return [Symbol]
      def attr_access_type(meth)
        case meth
        when :attr_reader then :r
        when :attr_writer then :w
        else :rw
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Boolean]
      def process_module_function_send?(node, ctx)
        recv, meth, *args = *node

        return false unless recv.nil? && meth == :module_function
        return true if ctx.inside_sclass

        return enable_default_module_function?(ctx) if args.empty?

        process_named_module_function(args, ctx)

        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @return [Boolean]
      def enable_default_module_function?(ctx)
        ctx.module_function_default = true
        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] args Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Object]
      def process_named_module_function(args, ctx)
        args.map { |arg| extract_name_sym(arg) }
            .compact
            .each do |sym|
          ctx.module_function_explicit[sym] = true

          retroactively_promote_module_function(
            sym,
            container: container_for(ctx)
          )
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] name_sym Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def retroactively_promote_module_function(name_sym, container:)
        @insertions.reverse_each do |ins|
          next unless ins.container == container
          next unless ins.node.type == :def
          next unless ins.node.children[0] == name_sym

          ins.scope = :class
          ins.visibility = :public
          ins.module_function = true
          ins.included_instance_visibility ||= :private
          break
        end
      end

      # Detect `private_class_method` / `protected_class_method` / `public_class_method` and update class-level
      # visibility.
      #
      # @private
      # @param [Parser::AST::Node] node a `:send` node
      # @param [VisibilityCtx] ctx current visibility context
      # @return [Boolean] true if the node was a class visibility modifier
      def process_class_method_visibility_send?(node, ctx)
        recv, meth, *args = *node
        return false unless class_visibility_send?(recv, meth)

        visibility = class_method_visibility(meth)
        apply_class_method_visibility(args, ctx, visibility, container_for(ctx))

        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] recv Param documentation.
      # @param [Object] meth Param documentation.
      # @return [Object]
      def class_visibility_send?(recv, meth)
        %i[
          private_class_method
          protected_class_method
          public_class_method
        ].include?(meth) &&
          (recv.nil? || self_node?(recv))
      end

      # Method documentation.
      #
      # @private
      # @param [Object] meth Param documentation.
      # @return [Symbol]
      def class_method_visibility(meth)
        case meth
        when :private_class_method
          :private
        when :protected_class_method
          :protected
        else
          :public
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] args Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] visibility Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def apply_class_method_visibility(args, ctx, visibility, container)
        args.each do |arg|
          sym = extract_name_sym(arg)
          next unless sym

          ctx.explicit_class[sym] = visibility

          retroactively_set_visibility(sym, visibility, scope: :class, container: container)
        end
      end

      # Detect `private` / `protected` / `public` calls and update visibility state.
      #
      # Handles both bare modifiers (no args) that change defaults, and named
      # modifiers (`private :foo`) that retroactively update method visibility.
      # Also handles inline modifiers (`private def foo`).
      #
      # @private
      # @param [Parser::AST::Node] node a `:send` node
      # @param [VisibilityCtx] ctx current visibility context
      # @param [Parser::AST::Node, nil] pending_sig_anchor Sorbet `sig` node
      # @return [void]
      def process_visibility_send(node, ctx, pending_sig_anchor: nil)
        recv, meth, *args = *node

        return unless visibility_send?(recv, meth)

        process_visibility_args(args, ctx, meth, container_for(ctx), pending_sig_anchor)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] recv Param documentation.
      # @param [Object] meth Param documentation.
      # @return [Object]
      def visibility_send?(recv, meth)
        recv.nil? && %i[private protected public].include?(meth)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] args Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] meth Param documentation.
      # @param [Object] container Param documentation.
      # @param [Object] pending_sig_anchor Param documentation.
      # @return [Object]
      def process_visibility_args(args, ctx, meth, container, pending_sig_anchor)
        if args.empty?
          process_visibility_bare_modifier(ctx, meth)
        elsif inline_visibility_def?(args)
          process_visibility_inline_modifier(args.first, ctx, meth, container, pending_sig_anchor)
        else
          process_visibility_named_modifier(args, ctx, meth, container)
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] args Param documentation.
      # @return [Object]
      def inline_visibility_def?(args)
        args.length == 1 &&
          args.first.is_a?(Parser::AST::Node) &&
          %i[def defs].include?(args.first.type)
      end

      # Process a bare visibility modifier (no args).
      #
      # @private
      # @param [VisibilityCtx] ctx
      # @param [Symbol] meth
      # @return [void]
      def process_visibility_bare_modifier(ctx, meth)
        if ctx.inside_sclass
          ctx.default_class_vis = meth
        else
          ctx.default_instance_vis = meth
        end
      end

      # Process an inline visibility modifier (private def foo).
      #
      # @private
      # @param [Parser::AST::Node] def_node
      # @param [VisibilityCtx] ctx
      # @param [Symbol] meth
      # @param [String] container
      # @param [Parser::AST::Node, nil] pending_sig_anchor
      # @return [void]
      def process_visibility_inline_modifier(def_node, ctx, meth, container, pending_sig_anchor)
        anchor_node = pending_sig_anchor || def_node

        case def_node.type
        when :def
          process_visibility_inline_def(def_node, ctx, meth, container, anchor_node)
        when :defs
          @insertions << Insertion.new(def_node, :class, meth, container, nil, nil, anchor_node)
        end
      end

      # Process an inline def under a visibility modifier.
      #
      # @private
      # @param [Parser::AST::Node] def_node
      # @param [VisibilityCtx] ctx
      # @param [Symbol] meth
      # @param [String] container
      # @param [Parser::AST::Node] anchor_node
      # @return [void]
      def process_visibility_inline_def(def_node, ctx, meth, container, anchor_node)
        name, = *def_node

        if module_function_applies?(ctx, name)
          mod_vis = ctx.explicit_class[name] || ctx.default_class_vis
          @insertions << Insertion.new(def_node, :class, mod_vis, container, true, meth, anchor_node)
        elsif ctx.inside_sclass
          @insertions << Insertion.new(def_node, :class, meth, container, nil, nil, anchor_node)
        else
          @insertions << Insertion.new(def_node, :instance, meth, container, nil, nil, anchor_node)
        end
      end

      # Process a named visibility modifier (private :foo).
      #
      # @private
      # @param [Array<Parser::AST::Node>] args
      # @param [VisibilityCtx] ctx
      # @param [Symbol] meth
      # @param [String] container
      # @return [void]
      def process_visibility_named_modifier(args, ctx, meth, container)
        args.each do |arg|
          apply_visibility_modifier_arg(arg, ctx, meth, container)
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] arg Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] meth Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def apply_visibility_modifier_arg(arg, ctx, meth, container)
        sym = extract_name_sym(arg)
        return unless sym

        if ctx.inside_sclass
          apply_class_visibility_modifier(sym, ctx, meth, container)
        else
          apply_instance_visibility_modifier(sym, ctx, meth, container)
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] sym Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] meth Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def apply_class_visibility_modifier(sym, ctx, meth, container)
        ctx.explicit_class[sym] = meth

        retroactively_set_visibility(sym, meth, scope: :class, container: container)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] sym Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] meth Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def apply_instance_visibility_modifier(sym, ctx, meth, container)
        ctx.explicit_instance[sym] = meth
        retroactively_set_visibility(sym, meth, scope: :instance, container: container)
        retroactively_set_included_instance_visibility_for_module_function(sym, meth, container: container)
      end

      # Retroactively update the included instance visibility for a module_function method.
      #
      # @private
      # @param [Symbol] name_sym the method name
      # @param [Symbol] visibility the new visibility (:public, :protected, :private)
      # @param [String] container the container name
      # @return [void]
      def retroactively_set_included_instance_visibility_for_module_function(name_sym, visibility, container:)
        @insertions.reverse_each do |ins|
          next unless ins.container == container
          next unless ins.module_function
          next unless ins.node.type == :def
          next unless ins.node.children[0] == name_sym

          ins.included_instance_visibility = visibility
          break
        end
      end

      # Check if `module_function` semantics apply to a method at the current position.
      #
      # @private
      # @param [VisibilityCtx] ctx current visibility context
      # @param [Symbol] name the method name
      # @return [Boolean]
      def module_function_applies?(ctx, name)
        return false if ctx.inside_sclass

        ctx.module_function_default || ctx.module_function_explicit[name]
      end

      # Handle a def where module_function applies.
      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] name Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] anchor_node Param documentation.
      # @return [Object]
      def process_module_function_def(node, name, ctx, anchor_node)
        @insertions << Insertion.new(node, :class, ctx.explicit_class[name] || ctx.default_class_vis,
                                     container_for(ctx), true,
                                     ctx.explicit_instance[name] || :private, anchor_node)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @return [Object]
      def extend_self_applies?(ctx)
        ctx.container_is_module && ctx.extend_self && !ctx.inside_sclass
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] name Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] anchor_node Param documentation.
      # @return [Object]
      def process_extend_self_def(node, name, ctx, anchor_node)
        @insertions << Insertion.new(node, :class, ctx.explicit_instance[name] || ctx.default_instance_vis,
                                     container_for(ctx), nil, nil, anchor_node)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @param [Object] name Param documentation.
      # @return [Array]
      def def_scope_visibility(ctx, name)
        if ctx.inside_sclass
          [:class, ctx.explicit_class[name] || ctx.default_class_vis]
        else
          [:instance, ctx.explicit_instance[name] || ctx.default_instance_vis]
        end
      end

      # Retroactively update the visibility of a previously collected method.
      #
      # @private
      # @param [Symbol] name_sym the method name
      # @param [Symbol] visibility the new visibility
      # @param [Symbol] scope the method scope (`:instance` or `:class`)
      # @param [String] container the container name
      # @return [void]
      def retroactively_set_visibility(name_sym, visibility, scope:, container:)
        @insertions.reverse_each do |insertion|
          next unless visibility_target?(insertion, scope, container)
          next unless insertion_method_name(insertion.node) == name_sym

          insertion.visibility = visibility
          break
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] insertion Param documentation.
      # @param [Object] scope Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def visibility_target?(insertion, scope, container)
        insertion.container == container && insertion.scope == scope
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def insertion_method_name(node)
        case node.type
        when :def
          node.children[0]
        when :defs
          node.children[1]
        end
      end

      # Check if a node is a `self` literal.
      #
      # @private
      # @param [Parser::AST::Node, nil] node an AST node
      # @return [Boolean]
      def self_node?(node)
        node && node.type == :self
      end

      # Process all nodes in a class/module body for documentation insertion targets.
      #
      # Handles Sorbet `sig` nodes by deferring them as pending anchors for the
      # next method definition.
      #
      # @private
      # @param [Parser::AST::Node, nil] body the body node
      # @param [VisibilityCtx] ctx current visibility context
      # @return [void]
      def process_body(body, ctx)
        return unless body

        nodes = body.type == :begin ? body.children : [body]
        pending_sig_nodes = []

        nodes.each do |child|
          process_body_child(child, ctx, pending_sig_nodes)
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] child Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] pending_sig_nodes Param documentation.
      # @return [Object]
      def process_body_child(child, ctx, pending_sig_nodes)
        if sorbet_sig_node?(child)
          pending_sig_nodes << child
          return
        end

        process_stmt(child, ctx, pending_sig_anchor: pending_sig_nodes.first)
        pending_sig_nodes.clear
      end

      # Process a single AST node for documentation insertion targets.
      #
      # Dispatches to specific handlers based on node type (`:def`, `:defs`,
      # `:sclass`, `:send` with visibility modifiers, etc.) and records
      # `Insertion` objects for methods that need documentation.
      #
      # @private
      # @param [Parser::AST::Node, nil] node the AST node to process
      # @param [VisibilityCtx] ctx current visibility and container context
      # @param [Parser::AST::Node, nil] pending_sig_anchor Sorbet `sig` node waiting for a method
      # @return [void]
      def process_stmt(node, ctx, pending_sig_anchor: nil)
        return unless node
        return process_casgn_stmt(node) if node.type == :casgn

        handler = PROCESS_STMT_HANDLERS[node.type]

        if handler
          dispatch_process_stmt(handler, node, ctx, pending_sig_anchor)
        else
          process(node)
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def process_casgn_stmt(node)
        process(node) unless process_struct_casgn?(node)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] handler Param documentation.
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [Object] pending_sig_anchor Param documentation.
      # @return [Object]
      def dispatch_process_stmt(handler, node, ctx, pending_sig_anchor)
        if %i[process_def_stmt process_defs_stmt process_send_stmt].include?(handler)
          __send__(handler, node, ctx, pending_sig_anchor: pending_sig_anchor)
        else
          __send__(handler, node, ctx)
        end
      end

      # Check if a constant assignment is `Struct.new` and extract attribute insertions.
      #
      # @private
      # @param [Parser::AST::Node] node a `:casgn` node
      # @return [Boolean] true if the node was handled as a struct definition
      def process_struct_casgn?(node)
        _scope, _name, value = *node
        return false unless struct_new_node?(value)

        names = extract_struct_member_names(value)
        return true if names.empty?

        @attr_insertions << AttrInsertion.new(node, :instance, :public, struct_container_name(node), :rw, names)

        true
      end

      # Check if a node represents a `Struct.new` call.
      #
      # @private
      # @param [Parser::AST::Node, nil] node an AST node
      # @return [Boolean]
      def struct_new_node?(node)
        return false unless node.is_a?(Parser::AST::Node)
        return false unless node.type == :send

        recv, meth, *_args = *node
        return false unless meth == :new
        return false unless recv&.type == :const

        recv_name = const_name(recv)
        %w[Struct ::Struct].include?(recv_name)
      end

      # If `extend self` is active for this module, document all instance defs as module methods (M.foo).
      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def persist_extend_self_state(ctx, container)
        return unless ctx.extend_self

        promote_extend_self_container(container: container)
        (@module_states[container] ||= {})[:extend_self] = true
      end

      # Extract member names from a `Struct.new` call, stripping the type string argument if present.
      #
      # @private
      # @param [Parser::AST::Node] struct_new_node a `:send` node representing `Struct.new`
      # @return [Array<Symbol>] extracted member names
      def extract_struct_member_names(struct_new_node)
        _recv, _meth, *args = *struct_new_node

        # Drop trailing keyword/options hash, e.g. keyword_init: true
        args = args.reject { |arg| arg.is_a?(Parser::AST::Node) && arg.type == :hash }

        # Support Struct.new("Foo", :a, :b)
        args = args.drop(1) if args.length >= 2 && args.first.is_a?(Parser::AST::Node) && args.first.type == :str

        args.map { |arg| extract_name_sym(arg) }.compact
      end

      # Build the container name for a struct constant assignment.
      #
      # @private
      # @param [Parser::AST::Node] node a `:casgn` node
      # @return [String] the fully qualified container name
      def struct_container_name(node)
        scope, name, _value = *node

        prefix =
          if scope
            const_name(scope)
          elsif current_container == 'Object'
            nil
          else
            current_container
          end

        [prefix, name.to_s].compact.reject(&:empty?).join('::')
      end

      # Extract a Ruby symbol name from an AST node (`:sym` or `:str`).
      #
      # @private
      # @param [Parser::AST::Node] arg an AST node
      # @return [Symbol, nil] the extracted name or nil
      def extract_name_sym(arg)
        case arg.type
        when :sym then arg.children.first
        when :str then arg.children.first.to_sym
        end
      end

      # Build the fully qualified name for a constant node.
      #
      # @private
      # @param [Parser::AST::Node, nil] node a `:const` or `:cbase` node
      # @return [String] the resolved constant name
      def const_name(node)
        return 'Object' unless node

        case node.type
        when :const
          qualified_const_name(node)
        when :cbase
          ''
        else
          node.loc.expression.source
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def qualified_const_name(node)
        scope, name = *node
        scope_name = scope ? const_name(scope) : nil
        [scope_name, name].compact.join('::')
      end

      # Get the effective container name, using `container_override` when set.
      #
      # @private
      # @param [VisibilityCtx] ctx current visibility context
      # @return [String] the container name
      def container_for(ctx)
        ctx.container_override || current_container
      end

      # Get the current container name from the name stack.
      #
      # @private
      # @return [String] the current container (e.g. `"MyModule::MyClass"`) or `"Object"` if empty
      def current_container
        @name_stack.empty? ? 'Object' : @name_stack.join('::')
      end

      # Check if a node is a Sorbet `sig` declaration (bare `sig` send or `sig { ... }` block).
      #
      # @private
      # @param [Parser::AST::Node, nil] node an AST node
      # @return [Boolean]
      def sorbet_sig_node?(node)
        return false unless node.is_a?(Parser::AST::Node)

        sig_send_node?(node) || sig_block_node?(node)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def sig_block_node?(node)
        return false unless node.type == :block

        send_node, *_rest = *node
        sig_send_node?(send_node)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def sig_send_node?(node)
        return false unless node.type == :send

        recv, meth, *_args = *node
        recv.nil? && meth == :sig
      end

      # Promote instance methods to class methods for a container under `extend self`.
      #
      # @private
      # @param [String] container the container name
      # @return [void]
      def promote_extend_self_container(container:)
        @insertions.each do |ins|
          next unless ins.container == container
          next unless ins.node.type == :def
          next unless ins.scope == :instance
          next if ins.module_function

          ins.scope = :class
        end
      end
    end
  end
end
