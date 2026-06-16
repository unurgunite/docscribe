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
      # @!attribute [rw] node
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] scope
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] visibility
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] container
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] module_function
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] included_instance_visibility
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] anchor_node
      #   @return [Object]
      #   @param [Object] value
      Insertion = Struct.new(:node, :scope, :visibility, :container, :module_function, :included_instance_visibility,
                             :anchor_node)

      # @!attribute [rw] node
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] scope
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] visibility
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] container
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] access
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] names
      #   @return [Object]
      #   @param [Object] value
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
        #   @param [Object] value
        attr_accessor :default_instance_vis

        # @!attribute [rw] default_class_vis
        #   @return [Object]
        #   @param [Object] value
        attr_accessor :default_class_vis

        # @!attribute [rw] inside_sclass
        #   @return [Object]
        #   @param [Object] value
        attr_accessor :inside_sclass

        # @!attribute [rw] module_function_default
        #   @return [Object]
        #   @param [Object] value
        attr_accessor :module_function_default

        # @!attribute [rw] container_override
        #   @return [Object]
        #   @param [Object] value
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
        #   @param [Object] value
        attr_accessor :container_is_module

        # @!attribute [rw] extend_self
        #   @return [Object]
        #   @param [Object] value
        attr_accessor :extend_self

        # Create a fresh visibility context with Ruby-like defaults.
        #
        # @return [Boolean]
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
        # @return [Object]
        def dup
          VisibilityCtx.new.tap do |ctx|
            copy_visibility_state(ctx)
            copy_module_function_state(ctx)
            copy_container_state(ctx)
          end
        end

        private

        # Copy default instance/class visibility and sclass state into a new context.
        #
        # @private
        # @param [Object] ctx the target context to copy state into
        # @return [Object]
        def copy_visibility_state(ctx)
          ctx.default_instance_vis = default_instance_vis
          ctx.default_class_vis = default_class_vis
          ctx.inside_sclass = inside_sclass

          ctx.explicit_instance.merge!(explicit_instance)
          ctx.explicit_class.merge!(explicit_class)
        end

        # Copy module_function default and explicit state into a new context.
        #
        # @private
        # @param [Object] ctx the target context to copy state into
        # @return [Object]
        def copy_module_function_state(ctx)
          ctx.module_function_default = module_function_default
          ctx.module_function_explicit.merge!(module_function_explicit)
        end

        # Copy container override, module flag, and extend_self state into a new context.
        #
        # @private
        # @param [Object] ctx the target context to copy state into
        # @return [Object]
        def copy_container_state(ctx)
          ctx.container_override = container_override
          ctx.container_is_module = container_is_module
          ctx.extend_self = extend_self
        end
      end

      # @!attribute [r] insertions
      #   @return [Object]
      attr_reader :insertions

      # @!attribute [r] attr_insertions
      #   @return [Object]
      attr_reader :attr_insertions

      # Create a collector for the given source buffer.
      #
      # @param [Object] buffer source buffer for anchor location lookups
      # @return [Hash]
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
      # @param [Object] node an AST node
      # @return [Object]
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
      # @param [Object] node an AST node
      # @return [Object]
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
      # @param [Object] node a `:casgn` node
      # @return [Object] the original node
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
      # @param [Object] node an AST node
      # @return [Object]
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
      # @param [Object] node an AST node
      # @return [Object]
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
      # @param [Object] node an AST node
      # @param [Object] ctx current visibility context
      # @param [Object] pending_sig_anchor Sorbet `sig` node waiting for a method
      # @return [Object]
      def process_def_stmt(node, ctx, pending_sig_anchor:)
        name, = *node
        anchor_node = pending_sig_anchor || node

        return process_module_function_def(node, name, ctx, anchor_node) if module_function_applies?(ctx, name)
        return process_extend_self_def(node, name, ctx, anchor_node) if extend_self_applies?(ctx)

        scope, visibility = def_scope_visibility(ctx, name)

        @insertions << Insertion.new(node, scope, visibility, container_for(ctx), nil, nil, anchor_node)
      end

      # Process a `:defs` node (singleton method) for documentation insertion.
      #
      # @private
      # @param [Object] node the `:defs` AST node
      # @param [Object] ctx current visibility context
      # @param [Object] pending_sig_anchor Sorbet `sig` node waiting for a method
      # @return [Object]
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
      # @param [Object] node an AST node
      # @param [Object] ctx current visibility context
      # @param [nil] pending_sig_anchor Param documentation.
      # @return [Object]
      def process_sclass_stmt(node, ctx, pending_sig_anchor: nil) # rubocop:disable Lint/UnusedMethodArgument
        # `class << self` — affects default visibility for singleton methods and changes scope.
        recv, body = *node
        inner_ctx = ctx.dup

        configure_sclass_context(inner_ctx, recv)

        process_body(body, inner_ctx)
      end

      # Configure the new context with sclass receiver tracking and container override.
      #
      # @private
      # @param [Object] ctx the inner context to configure
      # @param [Object] recv the receiver node of `class <<`
      # @return [Object]
      def configure_sclass_context(ctx, recv)
        ctx.inside_sclass = sclass_receiver?(recv)
        ctx.container_override = sclass_container_override(recv)
      end

      # Check if the receiver is `self` or a constant reference (enables sclass semantics).
      #
      # @private
      # @param [Object] recv the receiver node of `class <<`
      # @return [Object]
      def sclass_receiver?(recv)
        self_node?(recv) || const_receiver?(recv)
      end

      # Return the constant name for a non-self receiver, or nil for `class << self`.
      #
      # @private
      # @param [Object] recv the receiver node of `class <<`
      # @return [nil] the container name for constant receivers, nil for `self`
      def sclass_container_override(recv)
        return nil if self_node?(recv)
        return const_name(recv) if const_receiver?(recv)

        nil
      end

      # Process a `:send` node for documentation insertion.
      #
      # @private
      # @param [Object] node an AST node
      # @param [Object] ctx current visibility context
      # @param [Object] pending_sig_anchor Sorbet `sig` node waiting for a method
      # @return [Object]
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
      # @param [Object] node the class declaration node
      # @param [Object] super_node the superclass expression
      # @return [Object]
      def process_struct_class(node, super_node)
        return unless struct_new_node?(super_node)

        names = extract_struct_member_names(super_node)
        return if names.empty?

        @attr_insertions << AttrInsertion.new(node, :instance, :public, current_container, :rw, names)
      end

      # Detect `attr_reader` / `attr_writer` / `attr_accessor` calls and record attribute insertions.
      #
      # @private
      # @param [Object] node a `:send` node
      # @param [Object] ctx current visibility context
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
      # @param [Object] node a `:send` node
      # @param [Object] ctx current visibility context
      # @return [Boolean] true if `extend self` was detected
      def process_extend_self_send?(node, ctx)
        recv, meth, *args = *node

        return false unless extend_self_send?(ctx, recv, meth, args)

        persist_extend_self(ctx)

        true
      end

      # Mark the context and module state as using `extend self`.
      #
      # @private
      # @param [Object] ctx current visibility context
      # @return [Object]
      def persist_extend_self(ctx)
        ctx.extend_self = true

        container = container_for(ctx)
        (@module_states[container] ||= {})[:extend_self] = true
      end

      # Check if a `:send` node is an `extend self` call inside a module.
      #
      # @private
      # @param [Object] ctx current visibility context
      # @param [Object] recv the receiver of the send node
      # @param [Object] meth the method name being called
      # @param [Object] args the arguments to the method call
      # @return [Object, Boolean, Boolean, Boolean, Object]
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
      # @param [Object] node an AST node
      # @return [Boolean]
      def const_receiver?(node)
        return false unless node.is_a?(Parser::AST::Node)

        %i[const cbase].include?(node.type)
      end

      # Check if a send node is an attr_reader/attr_writer/attr_accessor call.
      #
      # @private
      # @param [Object] recv the receiver of the send node
      # @param [Object] meth the method name being called
      # @return [Boolean]
      def attr_send?(recv, meth)
        recv.nil? && %i[attr_reader attr_writer attr_accessor].include?(meth)
      end

      # Determine the scope and visibility for an attribute based on sclass context.
      #
      # @private
      # @param [Object] ctx current visibility context
      # @return [Array]
      def attr_scope_visibility(ctx)
        if ctx.inside_sclass
          [:class, ctx.default_class_vis]
        else
          [:instance, ctx.default_instance_vis]
        end
      end

      # Map the attr method name to an access type symbol.
      #
      # @private
      # @param [Object] meth the method name (:attr_reader, :attr_writer, or :attr_accessor)
      # @return [Symbol] :r for reader, :w for writer, :rw for accessor
      def attr_access_type(meth)
        case meth
        when :attr_reader then :r
        when :attr_writer then :w
        else :rw
        end
      end

      # Detect `module_function` calls and update the visibility context accordingly.
      #
      # @private
      # @param [Object] node the `:send` node
      # @param [Object] ctx current visibility context
      # @return [Boolean] true if the node was a module_function call
      def process_module_function_send?(node, ctx)
        recv, meth, *args = *node

        return false unless recv.nil? && meth == :module_function
        return true if ctx.inside_sclass

        return enable_default_module_function?(ctx) if args.empty?

        process_named_module_function(args, ctx)

        true
      end

      # Enable default module_function for all subsequent method definitions in the module.
      #
      # @private
      # @param [Object] ctx current visibility context
      # @return [Boolean] true
      def enable_default_module_function?(ctx)
        ctx.module_function_default = true
        true
      end

      # Process a `module_function :foo, :bar` call with named arguments.
      #
      # @private
      # @param [Object] args the named method arguments
      # @param [Object] ctx current visibility context
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

      # Retroactively promote a previously collected method to module_function (class scope).
      #
      # @private
      # @param [Object] name_sym the method name to promote
      # @param [Object] container the container name
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
      # @param [Object] node a `:send` node
      # @param [Object] ctx current visibility context
      # @return [Boolean] true if the node was a class visibility modifier
      def process_class_method_visibility_send?(node, ctx)
        recv, meth, *args = *node
        return false unless class_visibility_send?(recv, meth)

        visibility = class_method_visibility(meth)
        apply_class_method_visibility(args, ctx, visibility, container_for(ctx))

        true
      end

      # Check if a send node is a private/protected/public_class_method call.
      #
      # @private
      # @param [Object] recv the receiver of the send node
      # @param [Object] meth the method name being called
      # @return [Boolean, Boolean, Object]
      def class_visibility_send?(recv, meth)
        %i[
          private_class_method
          protected_class_method
          public_class_method
        ].include?(meth) &&
          (recv.nil? || self_node?(recv))
      end

      # Map a class method visibility modifier name to its visibility symbol.
      #
      # @private
      # @param [Object] meth the method name (:private_class_method, etc.)
      # @return [Symbol] :private, :protected, or :public
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

      # Apply a visibility modifier to named class methods and retroactively update their visibility.
      #
      # @private
      # @param [Object] args the method name nodes
      # @param [Object] ctx current visibility context
      # @param [Object] visibility the visibility to apply (:public, :protected, :private)
      # @param [Object] container the container name
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
      # @param [Object] node a `:send` node
      # @param [Object] ctx current visibility context
      # @param [nil] pending_sig_anchor Sorbet `sig` node
      # @return [Object]
      def process_visibility_send(node, ctx, pending_sig_anchor: nil)
        recv, meth, *args = *node

        return unless visibility_send?(recv, meth)

        process_visibility_args(args, ctx, meth, container_for(ctx), pending_sig_anchor)
      end

      # Check if a send node is a private/protected/public call with no receiver.
      #
      # @private
      # @param [Object] recv the receiver of the send node
      # @param [Object] meth the method name being called
      # @return [Boolean]
      def visibility_send?(recv, meth)
        recv.nil? && %i[private protected public].include?(meth)
      end

      # Dispatch visibility modifier handling based on whether args are absent, inline defs, or named symbols.
      #
      # @private
      # @param [Object] args the arguments to the visibility modifier
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @param [Object] container the container name
      # @param [Object] pending_sig_anchor Sorbet `sig` node waiting for a method
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

      # Check if visibility modifier args contain a single inline def/defs node.
      #
      # @private
      # @param [Object] args the arguments to the visibility modifier
      # @return [Boolean]
      def inline_visibility_def?(args)
        args.length == 1 &&
          args.first.is_a?(Parser::AST::Node) &&
          %i[def defs].include?(args.first.type)
      end

      # Process a bare visibility modifier (no args).
      #
      # @private
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @return [Object]
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
      # @param [Object] def_node Param documentation.
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @param [Object] container the container name
      # @param [Object] pending_sig_anchor Sorbet `sig` node waiting for a method
      # @return [Object]
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
      # @param [Object] def_node Param documentation.
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @param [Object] container the container name
      # @param [Object] anchor_node the anchor node for comment placement
      # @return [Object]
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
      # @param [Object] args the destructured arguments from Struct.new
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @param [Object] container the container name
      # @return [Object]
      def process_visibility_named_modifier(args, ctx, meth, container)
        args.each do |arg|
          apply_visibility_modifier_arg(arg, ctx, meth, container)
        end
      end

      # Apply a visibility modifier to a single named method symbol, dispatching to class or instance handling.
      #
      # @private
      # @param [Object] arg the AST node for the method name
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @param [Object] container the container name
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

      # Record and retroactively apply a class-scope visibility modifier for a named method.
      #
      # @private
      # @param [Object] sym the method name
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @param [Object] container the container name
      # @return [Object]
      def apply_class_visibility_modifier(sym, ctx, meth, container)
        ctx.explicit_class[sym] = meth

        retroactively_set_visibility(sym, meth, scope: :class, container: container)
      end

      # Record and retroactively apply an instance-scope visibility modifier for a named method.
      #
      # @private
      # @param [Object] sym the method name
      # @param [Object] ctx current visibility context
      # @param [Object] meth the visibility method (:private, :protected, :public)
      # @param [Object] container the container name
      # @return [Object]
      def apply_instance_visibility_modifier(sym, ctx, meth, container)
        ctx.explicit_instance[sym] = meth
        retroactively_set_visibility(sym, meth, scope: :instance, container: container)
        retroactively_set_included_instance_visibility_for_module_function(sym, meth, container: container)
      end

      # Retroactively update the included instance visibility for a module_function method.
      #
      # @private
      # @param [Object] name_sym the method name
      # @param [Object] visibility the new visibility (:public, :protected, :private)
      # @param [Object] container the container name
      # @return [Object]
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
      # @param [Object] ctx current visibility context
      # @param [Object] name the method name
      # @return [Object]
      def module_function_applies?(ctx, name)
        return false if ctx.inside_sclass

        ctx.module_function_default || ctx.module_function_explicit[name]
      end

      # Handle a def where module_function applies, recording it with class scope and module_function semantics.
      #
      # @private
      # @param [Object] node the `:def` AST node
      # @param [Object] name the method name
      # @param [Object] ctx current visibility context
      # @param [Object] anchor_node the anchor node for comment placement
      # @return [Object]
      def process_module_function_def(node, name, ctx, anchor_node)
        @insertions << Insertion.new(node, :class, ctx.explicit_class[name] || ctx.default_class_vis,
                                     container_for(ctx), true,
                                     ctx.explicit_instance[name] || :private, anchor_node)
      end

      # Check if extend self semantics should apply to the current definition.
      #
      # @private
      # @param [Object] ctx current visibility context
      # @return [Object, Boolean]
      def extend_self_applies?(ctx)
        ctx.container_is_module && ctx.extend_self && !ctx.inside_sclass
      end

      # Process a def under extend self semantics, recording it as a class method.
      #
      # @private
      # @param [Object] node the `:def` AST node
      # @param [Object] name the method name
      # @param [Object] ctx current visibility context
      # @param [Object] anchor_node the anchor node for comment placement
      # @return [Object]
      def process_extend_self_def(node, name, ctx, anchor_node)
        @insertions << Insertion.new(node, :class, ctx.explicit_instance[name] || ctx.default_instance_vis,
                                     container_for(ctx), nil, nil, anchor_node)
      end

      # Determine scope and visibility for a def based on sclass context and explicit visibility.
      #
      # @private
      # @param [Object] ctx current visibility context
      # @param [Object] name the method name
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
      # @param [Object] name_sym the method name
      # @param [Object] visibility the new visibility
      # @param [Object] scope the method scope (`:instance` or `:class`)
      # @param [Object] container the container name
      # @return [Object]
      def retroactively_set_visibility(name_sym, visibility, scope:, container:)
        @insertions.reverse_each do |insertion|
          next unless visibility_target?(insertion, scope, container)
          next unless insertion_method_name(insertion.node) == name_sym

          insertion.visibility = visibility
          break
        end
      end

      # Check if an Insertion matches the given scope and container for visibility updates.
      #
      # @private
      # @param [Object] insertion the Insertion struct to check
      # @param [Object] scope the scope to match (:instance or :class)
      # @param [Object] container the container name to match
      # @return [Boolean]
      def visibility_target?(insertion, scope, container)
        insertion.container == container && insertion.scope == scope
      end

      # Extract the method name symbol from a def or defs AST node.
      #
      # @private
      # @param [Object] node the `:def` or `:defs` AST node
      # @return [Object] the method name
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
      # @param [Object] node an AST node
      # @return [Boolean]
      def self_node?(node)
        !!(node && node.type == :self)
      end

      # Process all nodes in a class/module body for documentation insertion targets.
      #
      # Handles Sorbet `sig` nodes by deferring them as pending anchors for the
      # next method definition.
      #
      # @private
      # @param [Object] body the body node
      # @param [Object] ctx current visibility context
      # @return [Object]
      def process_body(body, ctx)
        return unless body

        nodes = body.type == :begin ? body.children : [body]
        pending_sig_nodes = [] #: Array[Parser::AST::Node]

        nodes.each do |child|
          process_body_child(child, ctx, pending_sig_nodes)
        end
      end

      # Process a single child node, collecting Sorbet sigs as pending anchors and dispatching statements.
      #
      # @private
      # @param [Object] child the child AST node to process
      # @param [Object] ctx current visibility context
      # @param [Object] pending_sig_nodes accumulator for Sorbet sig nodes
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
      # @param [Object] node the AST node to process
      # @param [Object] ctx current visibility and container context
      # @param [nil] pending_sig_anchor Sorbet `sig` node waiting for a method
      # @return [Object]
      def process_stmt(node, ctx, pending_sig_anchor: nil)
        return unless node
        return process_casgn_stmt(node) if node.type == :casgn

        method_name = :"process_#{node.type}_stmt"
        if respond_to?(method_name, true)
          __send__(method_name, node, ctx, pending_sig_anchor: pending_sig_anchor)
        else
          process(node)
        end
      end

      # Process a constant assignment statement, skipping Struct.new assignments.
      #
      # @private
      # @param [Object] node the `:casgn` AST node
      # @return [Object]
      def process_casgn_stmt(node)
        process(node) unless process_struct_casgn?(node)
      end

      # Check if a constant assignment is `Struct.new` and extract attribute insertions.
      #
      # @private
      # @param [Object] node a `:casgn` node
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
      # @param [Object] node an AST node
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
      #
      # @private
      # @param [Object] ctx current visibility context
      # @param [Object] container the container name
      # @return [Object]
      def persist_extend_self_state(ctx, container)
        return unless ctx.extend_self

        promote_extend_self_container(container: container)
        (@module_states[container] ||= {})[:extend_self] = true
      end

      # Extract member names from a `Struct.new` call, stripping the type string argument if present.
      #
      # @private
      # @param [Object] struct_new_node a `:send` node representing `Struct.new`
      # @return [Object] extracted member names
      def extract_struct_member_names(struct_new_node)
        _recv, _meth, *args = *struct_new_node
        args ||= [] #: Array[Parser::AST::Node]

        args.reject! { |arg| arg.is_a?(Parser::AST::Node) && arg.type == :hash }

        drop_first_if_str!(args) if args.length >= 2

        args.map { |arg| extract_name_sym(arg) }.compact
      end

      # Drop the first argument if it is a string (e.g. Struct.new("Name", ...)).
      #
      # @private
      # @param [Object] args the destructured arguments from Struct.new
      # @return [Object]
      def drop_first_if_str!(args)
        return unless args.first.is_a?(Parser::AST::Node)
        return unless args.first.type == :str

        args.shift
      end

      # Build the container name for a struct constant assignment.
      #
      # @private
      # @param [Object] node a `:casgn` node
      # @return [Object] the fully qualified container name
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
      # @param [Object] arg an AST node
      # @return [Object] the extracted name or nil
      def extract_name_sym(arg)
        case arg.type
        when :sym then arg.children.first
        when :str then arg.children.first.to_sym
        end
      end

      # Build the fully qualified name for a constant node.
      #
      # @private
      # @param [Object] node a `:const` or `:cbase` node
      # @return [Object, String, Object] the resolved constant name
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

      # Build a qualified constant name by joining scope and constant parts.
      #
      # @private
      # @param [Object] node the `:const` AST node
      # @return [Object] the qualified name (e.g. "Foo::Bar")
      def qualified_const_name(node)
        scope, name = *node
        scope_name = scope ? const_name(scope) : nil
        [scope_name, name].compact.join('::')
      end

      # Get the effective container name, using `container_override` when set.
      #
      # @private
      # @param [Object] ctx current visibility context
      # @return [Object] the container name
      def container_for(ctx)
        ctx.container_override || current_container
      end

      # Get the current container name from the name stack.
      #
      # @private
      # @return [String, Object] the current container (e.g. `"MyModule::MyClass"`) or `"Object"` if empty
      def current_container
        @name_stack.empty? ? 'Object' : @name_stack.join('::')
      end

      # Check if a node is a Sorbet `sig` declaration (bare `sig` send or `sig { ... }` block).
      #
      # @private
      # @param [Object] node an AST node
      # @return [Object]
      def sorbet_sig_node?(node)
        return false unless node.is_a?(Parser::AST::Node)

        sig_send_node?(node) || sig_block_node?(node)
      end

      # Check if a node is a Sorbet `sig { ... }` block.
      #
      # @private
      # @param [Object] node an AST node
      # @return [Object]
      def sig_block_node?(node)
        return false unless node.type == :block

        send_node, *_rest = *node
        sig_send_node?(send_node)
      end

      # Check if a node is a bare Sorbet `sig` send (without block).
      #
      # @private
      # @param [Object] node an AST node
      # @return [Object]
      def sig_send_node?(node)
        return false unless node.type == :send

        recv, meth, *_args = *node
        recv.nil? && meth == :sig
      end

      # Promote instance methods to class methods for a container under `extend self`.
      #
      # @private
      # @param [Object] container the container name
      # @return [Object]
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
