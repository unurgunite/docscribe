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
          c = VisibilityCtx.new
          c.default_instance_vis = default_instance_vis
          c.default_class_vis = default_class_vis
          c.inside_sclass = inside_sclass

          c.module_function_default = module_function_default
          c.module_function_explicit.merge!(module_function_explicit)

          c.explicit_instance.merge!(explicit_instance)
          c.explicit_class.merge!(explicit_class)

          c.container_override = container_override
          c.container_is_module = container_is_module
          c.extend_self = extend_self
          c
        end
      end

      # @!attribute [r] insertions
      #  @return [Array<Insertion>]
      attr_reader :insertions

      # @!attribute [r] attr_insertions
      #   @return [Array<AttrInsertion>]
      attr_reader :attr_insertions

      # Method documentation.
      #
      # @param [Parser::Source::Buffer] buffer
      # @return [Object]
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
        if ctx.extend_self
          promote_extend_self_container(container: container)
          @module_states[container] ||= {}
          @module_states[container][:extend_self] = true
        end

        @name_stack.pop
        node
      end

      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def on_casgn(node)
        return node if process_struct_casgn(node)

        node.children.each do |child|
          process(child) if child.is_a?(Parser::AST::Node)
        end

        node
      end

      private

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [nil] pending_sig_anchor Param documentation.
      # @return [Object]
      def process_stmt(node, ctx, pending_sig_anchor: nil)
        return unless node

        case node.type
        when :def
          name, _args, _body = *node
          anchor_node = pending_sig_anchor || node

          if module_function_applies?(ctx, name)
            scope = :class
            vis = ctx.explicit_class[name] || ctx.default_class_vis

            # module_function makes included instance method private by default,
            # but explicit named visibility can override it (e.g. `public :foo`).
            included_vis = ctx.explicit_instance[name] || :private

            @insertions << Insertion.new(node, scope, vis, container_for(ctx), true, included_vis, anchor_node)
            return
          end

          if extend_self_applies?(ctx)
            # Under `extend self` in a module, instance methods are callable as module methods (M.foo).
            scope = :class
            vis = ctx.explicit_instance[name] || ctx.default_instance_vis

            @insertions << Insertion.new(node, scope, vis, container_for(ctx), nil, nil, anchor_node)
            return
          end

          # existing behavior for non-module_function:
          if ctx.inside_sclass
            vis = ctx.explicit_class[name] || ctx.default_class_vis
            scope = :class
          else
            vis = ctx.explicit_instance[name] || ctx.default_instance_vis
            scope = :instance
          end

          @insertions << Insertion.new(node, scope, vis, container_for(ctx), nil, nil, anchor_node)

        when :defs
          recv, name, _args, _body = *node
          vis = ctx.explicit_class[name] || ctx.default_class_vis

          container =
            if const_receiver?(recv)
              const_name(recv)
            else
              container_for(ctx)
            end

          @insertions << Insertion.new(node, :class, vis, container, nil, nil, pending_sig_anchor || node)

        when :sclass
          # `class << self` — affects default visibility for singleton methods and changes scope.
          recv, body = *node
          inner_ctx = ctx.dup

          if self_node?(recv)
            # class << self
            inner_ctx.inside_sclass = true
            inner_ctx.container_override = nil
          elsif const_receiver?(recv)
            # class << Foo  (const receiver) — document methods under Foo
            inner_ctx.inside_sclass = true
            inner_ctx.container_override = const_name(recv)
          else
            # Unknown receiver (e.g. class << obj) — keep prior behavior
            inner_ctx.inside_sclass = false
            inner_ctx.container_override = nil
          end

          # NOTE: we intentionally do NOT reset default_class_vis here; we inherit via ctx.dup.
          process_body(body, inner_ctx)

        when :casgn
          if process_struct_casgn(node)
            # handled
          else
            process(node)
          end

        when :send
          if process_attr_send(node, ctx)
            # handled
          elsif process_extend_self_send(node, ctx)
            # handled
          elsif process_module_function_send(node, ctx)
            # handled
          elsif process_class_method_visibility_send(node, ctx)
            # handled
          else
            process_visibility_send(node, ctx, pending_sig_anchor: pending_sig_anchor)
          end

        else
          process(node)
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] super_node Param documentation.
      # @return [Object]
      def process_struct_class(node, super_node)
        return unless struct_new_node?(super_node)

        names = extract_struct_member_names(super_node)
        return if names.empty?

        @attr_insertions << AttrInsertion.new(
          node,          # insert above the class declaration
          :instance,     # struct members are instance readers/writers
          :public,       # Struct fields are public by default
          current_container,
          :rw,
          names
        )
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Boolean]
      def process_struct_casgn(node)
        _scope, _name, value = *node
        return false unless struct_new_node?(value)

        names = extract_struct_member_names(value)
        return true if names.empty?

        @attr_insertions << AttrInsertion.new(
          node, # insert above the constant assignment
          :instance,
          :public,
          struct_container_name(node),
          :rw,
          names
        )

        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def struct_new_node?(node)
        return false unless node.is_a?(Parser::AST::Node)
        return false unless node.type == :send

        recv, meth, *_args = *node
        return false unless meth == :new
        return false unless recv&.type == :const

        recv_name = const_name(recv)
        %w[Struct ::Struct].include?(recv_name)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] struct_new_node Param documentation.
      # @return [Object]
      def extract_struct_member_names(struct_new_node)
        _recv, _meth, *args = *struct_new_node

        # Drop trailing keyword/options hash, e.g. keyword_init: true
        args = args.reject { |arg| arg.is_a?(Parser::AST::Node) && arg.type == :hash }

        # Support Struct.new("Foo", :a, :b)
        args = args.drop(1) if args.length >= 2 && args.first.is_a?(Parser::AST::Node) && args.first.type == :str

        args.map { |arg| extract_name_sym(arg) }.compact
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
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

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Boolean]
      def process_extend_self_send(node, ctx)
        recv, meth, *args = *node

        return false unless ctx.container_is_module
        return false unless recv.nil? && meth == :extend
        return false if ctx.inside_sclass
        return false unless args.any? { |a| self_node?(a) }

        ctx.extend_self = true

        # Persist across reopened modules in this file.
        container = container_for(ctx)
        @module_states[container] ||= {}
        @module_states[container][:extend_self] = true

        true
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
      # @return [Object]
      def const_receiver?(node)
        return false unless node.is_a?(Parser::AST::Node)

        %i[const cbase].include?(node.type)
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Boolean]
      def process_attr_send(node, ctx)
        recv, meth, *args = *node
        return false unless recv.nil? && %i[attr_reader attr_writer attr_accessor].include?(meth)

        names = args.map { |a| extract_name_sym(a) }.compact
        return true if names.empty?

        scope = ctx.inside_sclass ? :class : :instance
        visibility = ctx.inside_sclass ? ctx.default_class_vis : ctx.default_instance_vis

        access =
          case meth
          when :attr_reader then :r
          when :attr_writer then :w
          else :rw
          end

        @attr_insertions << AttrInsertion.new(node, scope, visibility, container_for(ctx), access, names)

        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Boolean]
      def process_class_method_visibility_send(node, ctx)
        recv, meth, *args = *node

        return false unless %i[private_class_method protected_class_method public_class_method].include?(meth)
        return false unless recv.nil? || self_node?(recv)

        visibility =
          case meth
          when :private_class_method then :private
          when :protected_class_method then :protected
          else :public
          end

        container = container_for(ctx)

        args.each do |arg|
          sym = extract_name_sym(arg)
          next unless sym

          ctx.explicit_class[sym] = visibility
          retroactively_set_visibility(sym, visibility, scope: :class, container: container)
        end

        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @param [nil] pending_sig_anchor Param documentation.
      # @return [Object]
      def process_visibility_send(node, ctx, pending_sig_anchor: nil)
        recv, meth, *args = *node
        return unless recv.nil? && %i[private protected public].include?(meth)

        container = container_for(ctx)

        if args.empty?
          if ctx.inside_sclass
            ctx.default_class_vis = meth
          else
            ctx.default_instance_vis = meth
          end
          return
        end

        # Inline modifier: private def foo / private def self.foo
        if args.length == 1 && args[0].is_a?(Parser::AST::Node) && %i[def defs].include?(args[0].type)
          def_node = args[0]
          anchor_node = pending_sig_anchor || def_node

          case def_node.type
          when :def
            name, = *def_node

            if module_function_applies?(ctx, name)
              mod_vis = ctx.explicit_class[name] || ctx.default_class_vis
              included_vis = meth
              @insertions << Insertion.new(def_node, :class, mod_vis, container, true, included_vis, anchor_node)
            elsif ctx.inside_sclass
              @insertions << Insertion.new(def_node, :class, meth, container, nil, nil, anchor_node)
            else
              @insertions << Insertion.new(def_node, :instance, meth, container, nil, nil, anchor_node)
            end

            return

          when :defs
            @insertions << Insertion.new(def_node, :class, meth, container, nil, nil, anchor_node)
            return
          end
        end

        # Named visibility: private :foo
        args.each do |arg|
          sym = extract_name_sym(arg)
          next unless sym

          if ctx.inside_sclass
            ctx.explicit_class[sym] = meth
            retroactively_set_visibility(sym, meth, scope: :class, container: container)
          else
            ctx.explicit_instance[sym] = meth
            retroactively_set_visibility(sym, meth, scope: :instance, container: container)
            retroactively_set_included_instance_visibility_for_module_function(sym, meth, container: container)
          end
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] name_sym Param documentation.
      # @param [Object] visibility Param documentation.
      # @param [Object] container Param documentation.
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

      # Method documentation.
      #
      # @private
      # @param [Object] name_sym Param documentation.
      # @param [Object] visibility Param documentation.
      # @param [Object] scope Param documentation.
      # @param [Object] container Param documentation.
      # @return [Object]
      def retroactively_set_visibility(name_sym, visibility, scope:, container:)
        @insertions.reverse_each do |ins|
          next unless ins.container == container
          next unless ins.scope == scope

          n = ins.node
          method_name =
            case n.type
            when :def  then n.children[0]
            when :defs then n.children[1]
            end

          next unless method_name == name_sym

          ins.visibility = visibility
          break
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @param [Object] name Param documentation.
      # @return [Object]
      def module_function_applies?(ctx, name)
        return false if ctx.inside_sclass

        ctx.module_function_default || ctx.module_function_explicit[name]
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Boolean]
      def process_module_function_send(node, ctx)
        recv, meth, *args = *node
        return false unless recv.nil? && meth == :module_function
        return true if ctx.inside_sclass

        if args.empty?
          ctx.module_function_default = true
          return true
        end

        names = args.map { |arg| extract_name_sym(arg) }.compact
        names.each do |sym|
          ctx.module_function_explicit[sym] = true
          retroactively_promote_module_function(sym, container: container_for(ctx))
        end

        true
      end

      # Method documentation.
      #
      # @private
      # @param [Object] ctx Param documentation.
      # @return [Object]
      def container_for(ctx)
        ctx.container_override || current_container
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

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def self_node?(node)
        node && node.type == :self
      end

      # Method documentation.
      #
      # @private
      # @param [Object] arg Param documentation.
      # @return [Object]
      def extract_name_sym(arg)
        case arg.type
        when :sym then arg.children.first
        when :str then arg.children.first.to_sym
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
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

      # Method documentation.
      #
      # @private
      # @return [Object]
      def current_container
        @name_stack.empty? ? 'Object' : @name_stack.join('::')
      end

      # Method documentation.
      #
      # @private
      # @param [Object] body Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Object]
      def process_body(body, ctx)
        return unless body

        nodes = body.type == :begin ? body.children : [body]
        pending_sig_nodes = []

        nodes.each do |child|
          if sorbet_sig_node?(child)
            pending_sig_nodes << child
            next
          end

          process_stmt(child, ctx, pending_sig_anchor: pending_sig_nodes.first)
          pending_sig_nodes.clear
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def sorbet_sig_node?(node)
        return false unless node.is_a?(Parser::AST::Node)

        case node.type
        when :send
          recv, meth, *_args = *node
          recv.nil? && meth == :sig
        when :block
          send_node, *_rest = *node
          return false unless send_node&.type == :send

          recv, meth, *_args = *send_node
          recv.nil? && meth == :sig
        else
          false
        end
      end

      # Method documentation.
      #
      # @private
      # @param [Object] container Param documentation.
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
