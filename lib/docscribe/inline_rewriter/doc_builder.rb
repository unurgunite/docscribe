# frozen_string_literal: true

require 'docscribe/infer'
require 'docscribe/inline_rewriter/source_helpers'

module Docscribe
  module InlineRewriter
    module DocBuilder
      module_function

      def build(insertion, config:, signature_provider: nil)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return nil unless name

        indent = SourceHelpers.line_indent(node)
        scope = insertion.scope
        visibility = insertion.visibility
        container = insertion.container
        method_symbol = scope == :instance ? '#' : '.'

        provider = signature_provider || config.rbs_provider
        external_sig = provider&.signature_for(container: container, scope: scope, name: name)

        params_lines = build_params_lines(node, indent, external_sig: external_sig, config: config) if config.emit_param_tags?
        raise_types = config.emit_raise_tags? ? Docscribe::Infer.infer_raises_from_node(node) : []

        returns_spec = Docscribe::Infer.returns_spec_from_node(
          node,
          fallback_type: config.fallback_type,
          nil_as_optional: config.nil_as_optional?
        )

        normal_type = external_sig&.return_type || returns_spec[:normal]
        rescue_specs = returns_spec[:rescues] || []

        lines = []

        if config.emit_header?
          lines << "#{indent}# +#{container}#{method_symbol}#{name}+ -> #{normal_type}"
          lines << "#{indent}#"
        end

        lines << "#{indent}# #{config.default_message(scope, visibility)}"
        lines << "#{indent}#"

        if config.emit_visibility_tags?
          case visibility
          when :private
            lines << "#{indent}# @private"
          when :protected
            lines << "#{indent}# @protected"
          end
        end

        if insertion.respond_to?(:module_function) && insertion.module_function
          included_vis =
            if insertion.respond_to?(:included_instance_visibility) && insertion.included_instance_visibility
              insertion.included_instance_visibility
            else
              :private
            end

          lines << "#{indent}# @note module_function: when included, also defines ##{name} " \
            "(instance visibility: #{included_vis})"
        end

        lines.concat(params_lines) if params_lines
        raise_types.each { |rt| lines << "#{indent}# @raise [#{rt}]" } if config.emit_raise_tags?
        lines << "#{indent}# @return [#{normal_type}]" if config.emit_return_tag?(scope, visibility)

        if config.emit_rescue_conditional_returns?
          rescue_specs.each do |exceptions, rtype|
            lines << "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
          end
        end

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: name || '(unknown)', phase: 'DocBuilder.build')
        nil
      end

      def build_merge_additions(insertion, existing_lines:, config:, signature_provider: nil)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return '' unless name

        indent = SourceHelpers.line_indent(node)
        info = parse_existing_doc_tags(existing_lines)
        scope = insertion.scope
        visibility = insertion.visibility

        provider = signature_provider || config.rbs_provider
        external_sig = provider&.signature_for(container: insertion.container, scope: scope, name: name)

        returns_spec = Docscribe::Infer.returns_spec_from_node(
          node,
          fallback_type: config.fallback_type,
          nil_as_optional: config.nil_as_optional?
        )

        normal_type = external_sig&.return_type || returns_spec[:normal]
        rescue_specs = returns_spec[:rescues] || []

        lines = []
        lines << "#{indent}#" if existing_lines.any? && existing_lines.last.strip != '#'

        if config.emit_visibility_tags?
          if visibility == :private && !info[:has_private]
            lines << "#{indent}# @private"
          elsif visibility == :protected && !info[:has_protected]
            lines << "#{indent}# @protected"
          end
        end

        if insertion.respond_to?(:module_function) && insertion.module_function && !info[:has_module_function_note]
          included_vis = insertion.included_instance_visibility || :private
          lines << "#{indent}# @note module_function: when included, also defines ##{name} " \
            "(instance visibility: #{included_vis})"
        end

        if config.emit_param_tags?
          all_params = build_params_lines(node, indent, external_sig: external_sig, config: config)
          all_params&.each do |pl|
            pname = extract_param_name_from_param_line(pl)
            next if pname.nil? || info[:param_names].include?(pname)

            lines << pl
          end
        end

        if config.emit_raise_tags?
          inferred = Docscribe::Infer.infer_raises_from_node(node)
          existing = info[:raise_types] || {}
          missing = inferred.reject { |rt| existing[rt] }
          missing.each { |rt| lines << "#{indent}# @raise [#{rt}]" }
        end

        if config.emit_return_tag?(scope, visibility) && !info[:has_return]
          lines << "#{indent}# @return [#{normal_type}]"
        end

        if config.emit_rescue_conditional_returns? && !info[:has_return]
          rescue_specs.each do |exceptions, rtype|
            lines << "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
          end
        end

        useful = lines.reject { |l| l.strip == '#' }
        return '' if useful.empty?

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: name || '(unknown)', phase: 'DocBuilder.build_merge_additions')
        nil
      end

      def build_missing_merge_result(insertion, existing_lines:, config:, signature_provider: nil)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return { lines: [], reasons: [] } unless name

        indent = SourceHelpers.line_indent(node)
        info = parse_existing_doc_tags(existing_lines)
        scope = insertion.scope
        visibility = insertion.visibility

        provider = signature_provider || config.rbs_provider
        external_sig = provider&.signature_for(container: insertion.container, scope: scope, name: name)

        returns_spec = Docscribe::Infer.returns_spec_from_node(
          node,
          fallback_type: config.fallback_type,
          nil_as_optional: config.nil_as_optional?
        )

        normal_type = external_sig&.return_type || returns_spec[:normal]
        rescue_specs = returns_spec[:rescues] || []

        lines = []
        reasons = []

        if config.emit_visibility_tags?
          if visibility == :private && !info[:has_private]
            lines << "#{indent}# @private\n"
            reasons << { type: :missing_visibility, message: 'missing @private' }
          elsif visibility == :protected && !info[:has_protected]
            lines << "#{indent}# @protected\n"
            reasons << { type: :missing_visibility, message: 'missing @protected' }
          end
        end

        if insertion.respond_to?(:module_function) && insertion.module_function && !info[:has_module_function_note]
          included_vis = insertion.included_instance_visibility || :private
          lines << "#{indent}# @note module_function: when included, also defines ##{name} " \
            "(instance visibility: #{included_vis})\n"
          reasons << { type: :missing_module_function_note, message: 'missing module_function note' }
        end

        if config.emit_param_tags?
          all_params = build_params_lines(node, indent, external_sig: external_sig, config: config)

          all_params&.each do |pl|
            pname = extract_param_name_from_param_line(pl)
            next if pname.nil? || info[:param_names].include?(pname)

            lines << "#{pl}\n"
            reasons << { type: :missing_param, message: "missing @param #{pname}", extra: { param: pname } }
          end
        end

        if config.emit_raise_tags?
          inferred = Docscribe::Infer.infer_raises_from_node(node)
          existing = info[:raise_types] || {}
          missing = inferred.reject { |rt| existing[rt] }

          missing.each do |rt|
            lines << "#{indent}# @raise [#{rt}]\n"
            reasons << { type: :missing_raise, message: "missing @raise [#{rt}]", extra: { raise_type: rt } }
          end
        end

        if config.emit_return_tag?(scope, visibility) && !info[:has_return]
          lines << "#{indent}# @return [#{normal_type}]\n"
          reasons << { type: :missing_return, message: 'missing @return' }
        end

        if config.emit_rescue_conditional_returns? && !info[:has_return]
          rescue_specs.each do |exceptions, rtype|
            lines << "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}\n"
            reasons << {
              type: :missing_return,
              message: "missing conditional @return for #{exceptions.join(', ')}"
            }
          end
        end

        { lines: lines, reasons: reasons }
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: name || '(unknown)', phase: 'DocBuilder.build_missing_merge_result')
        { lines: [], reasons: [] }
      end

      def parse_existing_doc_tags(lines)
        param_names = {}
        has_return = false
        has_private = false
        has_protected = false
        has_module_function_note = false
        raise_types = {}

        Array(lines).each do |line|
          if (pname = extract_param_name_from_param_line(line))
            param_names[pname] = true
          end

          has_return ||= line.match?(/^\s*#\s*@return\b/)
          has_private ||= line.match?(/^\s*#\s*@private\b/)
          has_protected ||= line.match?(/^\s*#\s*@protected\b/)
          has_module_function_note ||= line.match?(/^\s*#\s*@note\s+module_function:/)

          extract_raise_types_from_line(line).each { |t| raise_types[t] = true }
        end

        {
          param_names: param_names,
          has_return: has_return,
          raise_types: raise_types,
          has_private: has_private,
          has_protected: has_protected,
          has_module_function_note: has_module_function_note
        }
      end

      def extract_raise_types_from_line(line)
        return [] unless line.match?(/^\s*#\s*@raise\b/)

        if (m = line.match(/^\s*#\s*@raise\s*\[([^\]]+)\]/))
          parse_raise_bracket_list(m[1])
        elsif (m = line.match(/^\s*#\s*@raise\s+([A-Z]\w*(?:::[A-Z]\w*)*)/))
          [m[1]]
        else
          []
        end
      rescue StandardError
        []
      end

      def parse_raise_bracket_list(s)
        s.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      def build_params_lines(node, indent, external_sig:, config:)
        fallback_type = config.fallback_type
        treat_options_keyword_as_hash = config.treat_options_keyword_as_hash?
        param_tag_style = config.param_tag_style
        param_documentation = config.param_documentation

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
            ty = external_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   pname,
                   nil,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :optarg
            pname, default = *a
            pname = pname.to_s
            default_src = default&.loc&.expression&.source
            ty = external_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   pname,
                   default_src,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

            hash_option_pairs(default).each do |pair|
              key_node, value_node = pair.children
              option_key = option_key_name(key_node)
              option_type = Infer::Literals.type_from_literal(value_node, fallback_type: fallback_type)
              option_default = node_default_literal(value_node)

              line = "#{indent}# @option #{pname} [#{option_type}] :#{option_key}"
              line += " (#{option_default})" if option_default
              line += ' Option documentation.'
              params << line
            end

          when :kwarg
            pname = a.children.first.to_s
            ty = external_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   "#{pname}:",
                   nil,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :kwoptarg
            pname, default = *a
            pname = pname.to_s
            default_src = default&.loc&.expression&.source
            ty = external_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   "#{pname}:",
                   default_src,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :restarg
            pname = (a.children.first || 'args').to_s
            ty =
              if external_sig&.rest_positional&.element_type
                "Array<#{external_sig.rest_positional.element_type}>"
              else
                Infer.infer_param_type(
                  "*#{pname}",
                  nil,
                  fallback_type: fallback_type,
                  treat_options_keyword_as_hash: treat_options_keyword_as_hash
                )
              end
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :kwrestarg
            pname = (a.children.first || 'kwargs').to_s
            ty = external_sig&.rest_keywords&.type ||
                 Infer.infer_param_type(
                   "**#{pname}",
                   nil,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :blockarg
            pname = (a.children.first || 'block').to_s
            ty = external_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   "&#{pname}",
                   nil,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :forward_arg
            # skip
          end
        end

        params.empty? ? nil : params
      end

      def format_param_tag(indent, name, type, documentation, style:)
        doc = documentation.to_s.strip
        type = type.to_s

        case style.to_s
        when 'name_first'
          line = "#{indent}# @param #{name} [#{type}]"
        else
          line = "#{indent}# @param [#{type}] #{name}"
        end

        doc.empty? ? line : "#{line} #{doc}"
      end

      def hash_option_pairs(node)
        return [] unless node&.type == :hash

        node.children.select { |child| child.is_a?(Parser::AST::Node) && child.type == :pair }
      end

      def option_key_name(key_node)
        case key_node&.type
        when :sym, :str
          key_node.children.first.to_s
        else
          key_node&.loc&.expression&.source.to_s.sub(/\A:/, '')
        end
      end

      def node_default_literal(node)
        node&.loc&.expression&.source
      end

      def extract_param_name_from_param_line(line)
        return Regexp.last_match(1) if line =~ /@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      def debug_warn(e, insertion:, name:, phase:)
        return unless debug?

        node = insertion&.node
        buf_name = node&.loc&.expression&.source_buffer&.name || '(unknown)'
        line = node&.loc&.expression&.line
        scope = insertion&.scope
        method_symbol = scope == :class ? '.' : '#'
        container = insertion&.container || 'Object'

        where = +buf_name.to_s
        where << ":#{line}" if line
        where << " #{container}#{method_symbol}#{name}"

        warn "Docscribe DEBUG: #{phase} failed at #{where}: #{e.class}: #{e.message}"
      end

      def debug?
        ENV['DOCSCRIBE_DEBUG'] == '1'
      end
    end
  end
end
