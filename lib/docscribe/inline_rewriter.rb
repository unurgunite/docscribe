# frozen_string_literal: true

require 'racc/parser'
require 'ast'
require 'parser/deprecation'
require 'parser/source/buffer'
require 'parser/source/range'
require 'parser/source/tree_rewriter'
require 'parser/ast/processor'

require 'docscribe/config'
require 'docscribe/infer'
require 'docscribe/parsing'

module Docscribe
  module InlineRewriter
    # +Docscribe::InlineRewriter.insert_comments+ -> Object
    #
    # Method documentation.
    #
    # @param [Object] code Param documentation.
    # @param [Boolean] rewrite Param documentation.
    # @param [nil] config Param documentation.
    # @return [Object]
    def self.insert_comments(code, rewrite: false, config: nil)
      buffer = Parser::Source::Buffer.new('(inline)')
      buffer.source = code
      ast = Docscribe::Parsing.parse_buffer(buffer)
      return code unless ast

      config ||= Docscribe::Config.load

      collector = Collector.new(buffer)
      collector.process(ast)

      rewriter = Parser::Source::TreeRewriter.new(buffer)

      collector.insertions
               .sort_by { |ins| ins.node.loc.expression.begin_pos }
               .reverse_each do |ins|
                 name = node_name(ins.node)
                 next unless config.process_method?(
                   container: ins.container,
                   scope: ins.scope,
                   visibility: ins.visibility,
                   name: name
                 )

                 bol_range = line_start_range(buffer, ins.node)

                 if rewrite
                   # If there is a comment block immediately above, remove it (and its trailing blank lines)
                   if (range = comment_block_removal_range(buffer, bol_range.begin_pos))
                     rewriter.remove(range)
                   end
                 elsif already_has_doc_immediately_above?(buffer, bol_range.begin_pos)
                   # Skip if a doc already exists immediately above
                   next
                 end

                 doc = build_doc_for_node(buffer, ins, config)
                 next unless doc && !doc.empty?

                 rewriter.insert_before(bol_range, doc)
      end

      rewriter.process
    end

    # +Docscribe::InlineRewriter.node_name+ -> Object
    #
    # Method documentation.
    #
    # @param [Object] node Param documentation.
    # @return [Object]
    def self.node_name(node)
      case node.type
      when :def
        node.children[0]
      when :defs
        node.children[1] # method name symbol
      end
    end

    # +Docscribe::InlineRewriter.line_start_range+ -> Range
    #
    # Method documentation.
    #
    # @param [Object] buffer Param documentation.
    # @param [Object] node Param documentation.
    # @return [Range]
    def self.line_start_range(buffer, node)
      start_pos = node.loc.expression.begin_pos
      src = buffer.source
      bol = src.rindex("\n", start_pos - 1) || -1
      Parser::Source::Range.new(buffer, bol + 1, bol + 1)
    end

    # +Docscribe::InlineRewriter.comment_block_removal_range+ -> Range
    #
    # Method documentation.
    #
    # @param [Object] buffer Param documentation.
    # @param [Object] def_bol_pos Param documentation.
    # @return [Range]
    def self.comment_block_removal_range(buffer, def_bol_pos)
      src = buffer.source
      lines = src.lines
      # Find def line index
      def_line_idx = src[0...def_bol_pos].count("\n")
      i = def_line_idx - 1

      # Walk up and skip blank lines directly above def
      i -= 1 while i >= 0 && lines[i].strip.empty?
      # Now if the nearest non-blank line isn't a comment, nothing to remove
      return nil unless i >= 0 && lines[i] =~ /^\s*#/

      # Find the start of the contiguous comment block
      start_idx = i
      start_idx -= 1 while start_idx >= 0 && lines[start_idx] =~ /^\s*#/
      start_idx += 1

      # End position is at def_bol_pos; start position is BOL of start_idx
      # Compute absolute buffer positions
      # Position of BOL for start_idx:
      start_pos = 0
      if start_idx.positive?
        # Sum lengths of all preceding lines
        start_pos = lines[0...start_idx].join.length
      end

      Parser::Source::Range.new(buffer, start_pos, def_bol_pos)
    end

    # +Docscribe::InlineRewriter.already_has_doc_immediately_above?+ -> Object
    #
    # Method documentation.
    #
    # @param [Object] buffer Param documentation.
    # @param [Object] insert_pos Param documentation.
    # @return [Object]
    def self.already_has_doc_immediately_above?(buffer, insert_pos)
      src = buffer.source
      lines = src.lines
      current_line_index = src[0...insert_pos].count("\n")
      i = current_line_index - 1
      i -= 1 while i >= 0 && lines[i].strip.empty?
      return false if i.negative?

      !!(lines[i] =~ /^\s*#/)
    end

    # +Docscribe::InlineRewriter.build_doc_for_node+ -> Object
    #
    # Method documentation.
    #
    # @param [Object] _buffer Param documentation.
    # @param [Object] insertion Param documentation.
    # @param [Object] config Param documentation.
    # @raise [StandardError]
    # @return [Object]
    # @return [nil] if StandardError
    def self.build_doc_for_node(_buffer, insertion, config)
      node = insertion.node
      indent = ' ' * node.loc.expression.column

      name =
        case node.type
        when :def then node.children[0]
        when :defs then node.children[1]
        end

      scope = insertion.scope
      visibility = insertion.visibility

      method_symbol = scope == :instance ? '#' : '.'
      container = insertion.container
      rbs_sig = config.rbs_provider&.signature_for(
        container: container,
        scope: scope,
        name: name
      )
      # Params
      params_block = build_params_block(node, indent, rbs_sig: rbs_sig) if config.emit_param_tags?

      # Raises (rescue and/or raise calls)
      raise_types = config.emit_raise_tags? ? Docscribe::Infer.infer_raises_from_node(node) : []

      # Returns: normal + conditional rescue returns
      spec = Docscribe::Infer.returns_spec_from_node(node)
      normal_type = rbs_sig&.return_type || spec[:normal]
      rescue_specs = spec[:rescues]

      lines = []
      if config.emit_header?
        lines << "#{indent}# +#{container}#{method_symbol}#{name}+ -> #{normal_type}"
        lines << "#{indent}#"
      end

      # Default doc text (configurable per scope/vis)
      lines << "#{indent}# #{config.default_message(scope, visibility)}"
      lines << "#{indent}#"

      if config.emit_visibility_tags?
        case visibility
        when :private then lines << "#{indent}# @private"
        when :protected then lines << "#{indent}# @protected"
        end
      end

      lines.concat(params_block) if params_block

      raise_types.each { |rt| lines << "#{indent}# @raise [#{rt}]" } if config.emit_raise_tags?

      lines << "#{indent}# @return [#{normal_type}]" if config.emit_return_tag?(scope, visibility)

      if config.emit_rescue_conditional_returns?
        rescue_specs.each do |(exceptions, rtype)|
          ex_display = exceptions.join(', ')
          lines << "#{indent}# @return [#{rtype}] if #{ex_display}"
        end
      end

      lines.map { |l| "#{l}\n" }.join
    rescue StandardError
      nil
    end

    # +Docscribe::InlineRewriter.build_params_block+ -> Object?
    #
    # Method documentation.
    #
    # @param [Object] node Param documentation.
    # @param [Object] indent Param documentation.
    # @return [Object?]
    def self.build_params_block(node, indent, rbs_sig: nil)
      args =
        case node.type
        when :def then node.children[1]
        when :defs then node.children[2] # args is children[2]
        end
      return nil unless args

      params = []

      (args.children || []).each do |a|
        case a.type
        when :arg
          pname = a.children.first.to_s
          ty = rbs_sig&.param_types&.[](pname) || Infer.infer_param_type(pname, nil)
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."

        when :optarg
          pname, default = *a
          pname = pname.to_s
          default_src = default&.loc&.expression&.source
          ty = rbs_sig&.param_types&.[](pname) || Infer.infer_param_type(pname, default_src)
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."

        when :kwarg
          pname = a.children.first.to_s
          ty = rbs_sig&.param_types&.[](pname) || Infer.infer_param_type("#{pname}:", nil)
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."

        when :kwoptarg
          pname, default = *a
          pname = pname.to_s
          default_src = default&.loc&.expression&.source
          ty = rbs_sig&.param_types&.[](pname) || Infer.infer_param_type("#{pname}:", default_src)
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."

        when :restarg
          pname = (a.children.first || 'args').to_s
          ty =
            if rbs_sig&.rest_positional&.element_type
              "Array<#{rbs_sig.rest_positional.element_type}>"
            else
              Infer.infer_param_type("*#{pname}", nil)
            end
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."

        when :kwrestarg
          pname = (a.children.first || 'kwargs').to_s
          ty = rbs_sig&.rest_keywords&.type || Infer.infer_param_type("**#{pname}", nil)
          params << "#{indent}# @param [#{ty}] #{pname} Param documentation."

        when :blockarg
          pname = (a.children.first || 'block').to_s
          ty = rbs_sig&.param_types&.[](pname) || Infer.infer_param_type("&#{pname}", nil)
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

      # +Docscribe::InlineRewriter::VisibilityCtx#initialize+ -> Object
      #
      # Method documentation.
      #
      # @return [Object]
      def initialize
        @default_instance_vis = :public
        @default_class_vis = :public
        @explicit_instance = {} # { name_sym => :private|:protected|:public }
        @explicit_class = {} # { name_sym => :private|:protected|:public }
        @inside_sclass = false
      end

      # +Docscribe::InlineRewriter::VisibilityCtx#dup+ -> Object
      #
      # Method documentation.
      #
      # @return [Object]
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

      # +Docscribe::InlineRewriter::Collector#initialize+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] buffer Param documentation.
      # @return [Object]
      def initialize(buffer)
        super()
        @buffer = buffer
        @insertions = []
        @name_stack = [] # e.g., ['Demo']
      end

      # +Docscribe::InlineRewriter::Collector#on_class+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def on_class(node)
        cname_node, _super_node, body = *node
        @name_stack.push(const_name(cname_node))
        ctx = VisibilityCtx.new
        process_body(body, ctx)
        @name_stack.pop
        node
      end

      # +Docscribe::InlineRewriter::Collector#on_module+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def on_module(node)
        cname_node, body = *node
        @name_stack.push(const_name(cname_node))
        ctx = VisibilityCtx.new
        process_body(body, ctx)
        @name_stack.pop
        node
      end

      # +Docscribe::InlineRewriter::Collector#on_def+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def on_def(node)
        @insertions << Insertion.new(node, :instance, :public, current_container)
        node
      end

      # +Docscribe::InlineRewriter::Collector#on_defs+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] node Param documentation.
      # @return [Object]
      def on_defs(node)
        @insertions << Insertion.new(node, :class, :public, current_container)
        node
      end

      private

      # +Docscribe::InlineRewriter::Collector#process_stmt+ -> Object
      #
      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Object]
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

      # +Docscribe::InlineRewriter::Collector#process_visibility_send+ -> Object
      #
      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Object]
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

      # +Docscribe::InlineRewriter::Collector#extract_name_sym+ -> Object
      #
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

      # +Docscribe::InlineRewriter::Collector#self_node?+ -> Object
      #
      # Method documentation.
      #
      # @private
      # @param [Object] node Param documentation.
      # @return [Object]
      def self_node?(node)
        node && node.type == :self
      end

      # +Docscribe::InlineRewriter::Collector#current_container+ -> Object
      #
      # Method documentation.
      #
      # @private
      # @return [Object]
      def current_container
        @name_stack.empty? ? 'Object' : @name_stack.join('::')
      end

      # +Docscribe::InlineRewriter::Collector#const_name+ -> Object
      #
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
          '' # leading ::
        else
          node.loc.expression.source # fallback
        end
      end

      # +Docscribe::InlineRewriter::Collector#process_body+ -> Object
      #
      # Method documentation.
      #
      # @private
      # @param [Object] body Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Object]
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
