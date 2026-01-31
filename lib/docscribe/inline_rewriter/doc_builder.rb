# frozen_string_literal: true

require 'docscribe/infer'
require 'docscribe/inline_rewriter/source_helpers'

module Docscribe
  module InlineRewriter
    # Builds the docstring text for an insertion (method node + computed metadata).
    module DocBuilder
      module_function

      # Build the full YARD-style doc block for one method insertion.
      #
      # @param insertion [Docscribe::InlineRewriter::Collector::Insertion]
      # @param config [Docscribe::Config]
      # @return [String, nil] doc block including trailing newlines, or nil on error
      def build(insertion, config:)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return nil unless name

        indent = ' ' * node.loc.expression.column

        scope = insertion.scope
        visibility = insertion.visibility
        container = insertion.container
        method_symbol = scope == :instance ? '#' : '.'

        rbs_sig = config.rbs_provider&.signature_for(container: container, scope: scope, name: name)

        # Params
        params_lines = config.emit_param_tags? ? build_params_lines(node, indent, rbs_sig: rbs_sig) : nil

        # Raises
        raise_types = config.emit_raise_tags? ? Docscribe::Infer.infer_raises_from_node(node) : []

        # Returns
        returns_spec = Docscribe::Infer.returns_spec_from_node(node)
        normal_type = rbs_sig&.return_type || returns_spec[:normal]
        rescue_specs = returns_spec[:rescues]

        lines = []

        if config.emit_header?
          lines << "#{indent}# +#{container}#{method_symbol}#{name}+ -> #{normal_type}"
          lines << "#{indent}#"
        end

        lines << "#{indent}# #{config.default_message(scope, visibility)}"
        lines << "#{indent}#"

        if config.emit_visibility_tags?
          case visibility
          when :private then lines << "#{indent}# @private"
          when :protected then lines << "#{indent}# @protected"
          end
        end

        lines.concat(params_lines) if params_lines

        raise_types.each { |rt| lines << "#{indent}# @raise [#{rt}]" } if config.emit_raise_tags?

        lines << "#{indent}# @return [#{normal_type}]" if config.emit_return_tag?(scope, visibility)

        if config.emit_rescue_conditional_returns?
          rescue_specs.each do |(exceptions, rtype)|
            lines << "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
          end
        end

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      # Build only the `@param` lines for a method.
      #
      # @param node [Parser::AST::Node] def/defs node
      # @param indent [String] indentation prefix
      # @param rbs_sig [Docscribe::Types::RBSProvider::Signature, nil]
      # @return [Array<String>, nil]
      def build_params_lines(node, indent, rbs_sig:)
        args =
          case node.type
          when :def then node.children[1]
          when :defs then node.children[2]
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
    end
  end
end
