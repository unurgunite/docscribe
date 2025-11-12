# frozen_string_literal: true

require 'parser/current'
require 'stingray_docs_internal/infer'

module StingrayDocsInternal
  module InlineRewriter
    # Public API: inserts docstrings into code and returns new code
    def self.insert_comments(code)
      buffer = Parser::Source::Buffer.new('(inline)')
      buffer.source = code
      parser = Parser::CurrentRuby.new
      ast = parser.parse(buffer)
      return code unless ast

      collector = Collector.new(buffer)
      collector.process(ast)

      # Prefer TreeRewriter in the future; Rewriter still works

      rewriter = Parser::Source::TreeRewriter.new(buffer)

      collector.insertions
               .sort_by { |ins| ins.node.loc.expression.begin_pos }
               .reverse_each do |ins|
        bol_range = line_start_range(buffer, ins.node)

        next if already_has_doc_immediately_above?(buffer, bol_range.begin_pos)

        doc = build_doc_for_node(buffer, ins)
        next unless doc && !doc.empty?

        rewriter.insert_before(bol_range, doc)
      end

      rewriter.process
    end

    # Helper: range at beginning of the line containing node
    def self.line_start_range(buffer, node)
      start_pos = node.loc.expression.begin_pos
      src = buffer.source
      bol = src.rindex("\n", start_pos - 1) || -1
      Parser::Source::Range.new(buffer, bol + 1, bol + 1)
    end

    def self.node_name(node)
      case node.type
      when :def
        node.children[0]
      when :defs
        node.children[1] # method name symbol
      end
    end

    def self.already_has_doc_immediately_above?(buffer, insert_pos)
      src = buffer.source
      lines = src.lines
      current_line_index = src[0...insert_pos].count("\n")
      i = current_line_index - 1
      i -= 1 while i >= 0 && lines[i].strip.empty?
      return false if i.negative?

      !!(lines[i] =~ /^\s*#/)
    end

    def self.build_doc_for_node(_buffer, insertion)
      node = insertion.node
      indent = ' ' * node.loc.expression.column

      name =
        case node.type
        when :def then node.children[0]
        when :defs then node.children[1] # [recv, name, args, body]
        end

      method_symbol = insertion.scope == :instance ? '#' : '.'
      container = insertion.container

      params_block = build_params_block(node, indent)
      return_type = Infer.infer_return_type_from_node(node)

      lines = []
      lines << "#{indent}# +#{container}#{method_symbol}#{name}+ -> #{return_type}"
      lines << "#{indent}#"
      lines << "#{indent}# Method documentation."
      lines << "#{indent}#"
      case insertion.visibility
      when :private then lines << "#{indent}# @private"
      when :protected then lines << "#{indent}# @protected"
      end
      lines.concat(params_block) if params_block
      lines << "#{indent}# @return [#{return_type}]"
      lines.map { |l| "#{l}\n" }.join
    end

    def self.build_params_block(node, indent)
      args =
        case node.type
        when :def then node.children[1]
        when :defs then node.children[2] # FIX: args is children[2], not [3]
        end
      return nil unless args

      params = []
      (args.children || []).each do |a|
        case a.type
        when :arg
          name = a.children.first.to_s
          ty = Infer.infer_param_type(name, nil)
          params << "#{indent}# @param [#{ty}] #{name} Param documentation."
        when :optarg
          name, default = *a
          ty = Infer.infer_param_type(name.to_s, default&.loc&.expression&.source)
          params << "#{indent}# @param [#{ty}] #{name} Param documentation."
        when :kwarg
          name = "#{a.children.first}:"
          ty = Infer.infer_param_type(name, nil)
          pname = name.sub(/:$/, '')
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."
        when :kwoptarg
          name, default = *a
          name = "#{name}:"
          ty = Infer.infer_param_type(name, default&.loc&.expression&.source)
          pname = name.sub(/:$/, '')
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."
        when :restarg
          name = "*#{a.children.first}"
          ty = Infer.infer_param_type(name, nil)
          pname = a.children.first.to_s
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."
        when :kwrestarg
          name = "**#{a.children.first || 'kwargs'}"
          ty = Infer.infer_param_type(name, nil)
          pname = (a.children.first || 'kwargs').to_s
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."
        when :blockarg
          name = "&#{a.children.first}"
          ty = Infer.infer_param_type(name, nil)
          pname = a.children.first.to_s
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."
        when :forward_arg
          # Ruby 3 '...' forwarding; skip
        end
      end
      params.empty? ? nil : params
    end

    class VisibilityCtx
      attr_accessor :default_instance_vis, :default_class_vis, :inside_sclass
      attr_reader :explicit_instance, :explicit_class

      def initialize
        @default_instance_vis = :public
        @default_class_vis = :public
        @explicit_instance = {} # { name_sym => :private|:protected|:public }
        @explicit_class = {} # { name_sym => :private|:protected|:public }
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

    # Walks nodes and records where to insert docstrings
    class Collector < Parser::AST::Processor
      Insertion = Struct.new(:node, :scope, :visibility, :container)

      attr_reader :insertions

      def initialize(buffer)
        super()
        @buffer = buffer
        @insertions = []
        @name_stack = [] # e.g., ['Demo']
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

      def on_def(node)
        @insertions << Insertion.new(node, :instance, :public, current_container)
        node
      end

      def on_defs(node)
        @insertions << Insertion.new(node, :class, :public, current_container)
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
          _, name, _args, _body = *node
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
          # bare keyword: affects current def-target
          if ctx.inside_sclass
            ctx.default_class_vis = meth
          else
            ctx.default_instance_vis = meth
          end
        else
          # explicit list: affects current def-target
          args.each do |arg|
            sym = extract_name_sym(arg)
            next unless sym

            if ctx.inside_sclass
              ctx.explicit_class[sym] = meth
            else
              ctx.explicit_instance[sym] = meth
            end

            target = ctx.inside_sclass ? 'class' : 'instance'
            if args.empty?
              puts "[vis] bare #{meth} -> default_#{target}_vis=#{meth}"
            else
              puts "[vis] explicit #{meth} -> #{target} names=#{args.map { |a| extract_name_sym(a) }.inspect}"
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
          '' # leading ::
        else
          node.loc.expression.source # fallback
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
