# frozen_string_literal: true

require 'docscribe/infer'
require 'docscribe/inline_rewriter/source_helpers'

module Docscribe
  module InlineRewriter
    # Builds a full docstring block for a single method insertion.
    #
    # Responsibilities:
    # - Combine config decisions (emit header/params/return/raise/visibility tags)
    # - Use RBS types (when enabled and available) for `@param` and `@return`
    # - Fall back to AST heuristics from {Docscribe::Infer} when RBS is not available
    module DocBuilder
      module_function

      # Build a doc block for a method insertion.
      #
      # The returned string includes trailing newlines and is intended to be inserted
      # at the beginning-of-line directly above the method definition.
      #
      # @note module_function: when included, also defines #build (instance visibility: private)
      # @param insertion [Docscribe::InlineRewriter::Collector::Insertion]
      # @param config [Docscribe::Config]
      # @raise [StandardError]
      # @return [String, nil] doc block string, or nil on error
      def build(insertion, config:)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return nil unless name

        indent = SourceHelpers.line_indent(node)

        scope = insertion.scope
        visibility = insertion.visibility
        container = insertion.container
        method_symbol = scope == :instance ? '#' : '.'

        # Best-effort RBS signature. If unavailable, returns nil, and we fall back to inference.
        rbs_sig = config.rbs_provider&.signature_for(container: container, scope: scope, name: name)

        # Params
        params_lines = build_params_lines(node, indent, rbs_sig: rbs_sig, config: config) if config.emit_param_tags?

        # Raises
        raise_types = config.emit_raise_tags? ? Docscribe::Infer.infer_raises_from_node(node) : []

        # Returns
        returns_spec = Docscribe::Infer.returns_spec_from_node(
          node,
          fallback_type: config.fallback_type,
          nil_as_optional: config.nil_as_optional?
        )

        normal_type = rbs_sig&.return_type || returns_spec[:normal]
        rescue_specs = returns_spec[:rescues]

        lines = []

        if config.emit_header?
          lines << "#{indent}# +#{container}#{method_symbol}#{name}+ -> #{normal_type}"
          lines << "#{indent}#"
        end

        lines << "#{indent}# #{config.default_message(scope, visibility)}"
        lines << "#{indent}#"

        # Ruby visibility of the documented surface (the method we are attaching docs to)
        if config.emit_visibility_tags?
          case visibility
          when :private then lines << "#{indent}# @private"
          when :protected then lines << "#{indent}# @protected"
          end
        end

        # module_function dual-surface note (single line; no heredoc/newline surprises)
        if insertion.respond_to?(:module_function) && insertion.module_function
          included_vis =
            if insertion.respond_to?(:included_instance_visibility) && insertion.included_instance_visibility
              insertion.included_instance_visibility
            else
              :private
            end

          lines << "#{indent}# @note module_function: when included, also defines ##{name} (instance visibility: #{included_vis})"
        end

        lines.concat(params_lines) if params_lines

        raise_types.each { |rt| lines << "#{indent}# @raise [#{rt}]" } if config.emit_raise_tags?

        lines << "#{indent}# @return [#{normal_type}]" if config.emit_return_tag?(scope, visibility)

        if config.emit_rescue_conditional_returns?
          rescue_specs.each do |(exceptions, rtype)|
            lines << "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
          end
        end
        # binding.irb
        lines.map { |l| "#{l}\n" }.join
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: name || '(unknown)', phase: 'DocBuilder.build')
        nil
      end

      # Build only missing lines to merge into an existing doc-like block.
      #
      # @note module_function: when included, also defines #build_merge_additions (instance visibility: private)
      # @param insertion [Docscribe::InlineRewriter::Collector::Insertion]
      # @param existing_lines [Array<String>]
      # @param config [Docscribe::Config]
      # @raise [StandardError]
      # @return [String, nil]
      def build_merge_additions(insertion, existing_lines:, config:)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return '' unless name

        indent = SourceHelpers.line_indent(node)

        info = parse_existing_doc_tags(existing_lines)

        scope = insertion.scope
        visibility = insertion.visibility

        rbs_sig = config.rbs_provider&.signature_for(container: insertion.container, scope: scope, name: name)

        returns_spec = Docscribe::Infer.returns_spec_from_node(
          node,
          fallback_type: config.fallback_type,
          nil_as_optional: config.nil_as_optional?
        )
        normal_type = rbs_sig&.return_type || returns_spec[:normal]
        rescue_specs = returns_spec[:rescues]

        lines = []

        # Separator if the existing block doesn't already end with a blank comment line
        lines << "#{indent}#" if existing_lines.any? && existing_lines.last.strip != '#'

        # Visibility tags for the documented surface
        if config.emit_visibility_tags?
          if visibility == :private && !info[:has_private]
            lines << "#{indent}# @private"
          elsif visibility == :protected && !info[:has_protected]
            lines << "#{indent}# @protected"
          end
        end

        # module_function dual-surface note
        if insertion.respond_to?(:module_function) && insertion.module_function && !info[:has_module_function_note]
          included_vis = insertion.included_instance_visibility || :private
          lines << "#{indent}# @note module_function: when included, also defines ##{name} (instance visibility: #{included_vis})"
        end

        # Params: add only missing @param entries
        if config.emit_param_tags?
          all_params = build_params_lines(node, indent, rbs_sig: rbs_sig, config: config)

          all_params&.each do |pl|
            pname = extract_param_name_from_param_line(pl)
            next if pname.nil? || info[:param_names].include?(pname)

            lines << pl
          end
        end

        # Raises: only add if there are no existing @raise lines
        if config.emit_raise_tags?
          inferred = Docscribe::Infer.infer_raises_from_node(node)
          existing = info[:raise_types] || {}

          missing = inferred.reject { |rt| existing[rt] }
          missing.each { |rt| lines << "#{indent}# @raise [#{rt}]" }
        end

        # Return: only add if there is no existing @return line at all
        lines << "#{indent}# @return [#{normal_type}]" if config.emit_return_tag?(scope, visibility) && !info[:has_return]

        # Conditional rescue @return tags: only add if there is no existing @return line at all
        if config.emit_rescue_conditional_returns? && !info[:has_return]
          rescue_specs.each do |(exceptions, rtype)|
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

      # +Docscribe::InlineRewriter::DocBuilder.parse_existing_doc_tags+ -> Hash
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #parse_existing_doc_tags (instance visibility: private)
      # @param lines [Object] Param documentation.
      # @return [Hash]
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

      # +Docscribe::InlineRewriter::DocBuilder.extract_raise_types_from_line+ -> Object
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_raise_types_from_line (instance visibility: private)
      # @param line [Object] Param documentation.
      # @raise [StandardError]
      # @return [Object]
      # @return [Array] if StandardError
      def extract_raise_types_from_line(line)
        return [] unless line.match?(/^\s*#\s*@raise\b/)

        # Common YARD forms:
        #   # @raise [Foo]
        #   # @raise [Foo, Bar]
        # Less common but seen:
        #   # @raise Foo
        #   # @raise FooError if ...
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

      # +Docscribe::InlineRewriter::DocBuilder.parse_raise_bracket_list+ -> Object
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #parse_raise_bracket_list (instance visibility: private)
      # @param s [Object] Param documentation.
      # @return [Object]
      def parse_raise_bracket_list(s)
        s.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      # Build only `@param` lines for a def/defs node.
      #
      # @note module_function: when included, also defines #build_params_lines (instance visibility: private)
      # @param node [Parser::AST::Node] `:def` or `:defs` node
      # @param indent [String] indentation prefix (spaces/tabs)
      # @param rbs_sig [Docscribe::Types::RBSProvider::Signature, nil]
      # @param config [Object] Param documentation.
      # @return [Array<String>, nil]
      def build_params_lines(node, indent, rbs_sig:, config:)
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
            ty = rbs_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   pname, nil,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :optarg
            pname, default = *a
            pname = pname.to_s
            default_src = default&.loc&.expression&.source
            ty = rbs_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   pname, default_src,
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
            ty = rbs_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   "#{pname}:", nil,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :kwoptarg
            pname, default = *a
            pname = pname.to_s
            default_src = default&.loc&.expression&.source
            ty = rbs_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   "#{pname}:", default_src,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :restarg
            pname = (a.children.first || 'args').to_s
            ty =
              if rbs_sig&.rest_positional&.element_type
                "Array<#{rbs_sig.rest_positional.element_type}>"
              else
                Infer.infer_param_type(
                  "*#{pname}", nil,
                  fallback_type: fallback_type,
                  treat_options_keyword_as_hash: treat_options_keyword_as_hash
                )
              end
            params << format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)

          when :kwrestarg
            pname = (a.children.first || 'kwargs').to_s
            ty =
              rbs_sig&.rest_keywords&.type ||
              Infer.infer_param_type(
                "**#{pname}", nil,
                fallback_type: fallback_type,
                treat_options_keyword_as_hash: treat_options_keyword_as_hash
              )
            params << format_param_tag(indent, pname, ty, config.param_documentation, style: param_tag_style)

          when :blockarg
            pname = (a.children.first || 'block').to_s
            ty = rbs_sig&.param_types&.[](pname) ||
                 Infer.infer_param_type(
                   "&#{pname}", nil,
                   fallback_type: fallback_type,
                   treat_options_keyword_as_hash: treat_options_keyword_as_hash
                 )
            params << format_param_tag(indent, pname, ty, config.param_documentation, style: param_tag_style)

          when :forward_arg
            # Ruby 3 '...' forwarding; skip
          end
        end

        params.empty? ? nil : params
      end

      # +Docscribe::InlineRewriter::DocBuilder.extract_param_name_from_param_line+ -> NilClass
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_param_name_from_param_line (instance visibility: private)
      # @param line [Object] Param documentation.
      # @return [NilClass]
      def extract_param_name_from_param_line(line)
        return Regexp.last_match(1) if line =~ /@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # +Docscribe::InlineRewriter::DocBuilder.debug_warn+ -> Object
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #debug_warn (instance visibility: private)
      # @param e [Object] Param documentation.
      # @param insertion [Object] Param documentation.
      # @param name [Object] Param documentation.
      # @param phase [Object] Param documentation.
      # @return [Object]
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

      # +Docscribe::InlineRewriter::DocBuilder.debug?+ -> Object
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #debug? (instance visibility: private)
      # @return [Object]
      def debug?
        ENV['DOCSCRIBE_DEBUG'] == '1'
      end

      # +Docscribe::InlineRewriter::DocBuilder.hash_option_pairs+ -> Object
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #hash_option_pairs (instance visibility: private)
      # @param hash_node [Object] Param documentation.
      # @return [Object]
      def hash_option_pairs(hash_node)
        return [] unless hash_node&.type == :hash

        hash_node.children.select { |child| child.type == :pair }
      end

      # +Docscribe::InlineRewriter::DocBuilder.option_key_name+ -> Object
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #option_key_name (instance visibility: private)
      # @param node [Object] Param documentation.
      # @return [Object]
      def option_key_name(node)
        case node&.type
        when :sym, :str
          node.children.first.to_s
        else
          node&.loc&.expression&.source.to_s
        end
      end

      # +Docscribe::InlineRewriter::DocBuilder.node_default_literal+ -> Object
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #node_default_literal (instance visibility: private)
      # @param node [Object] Param documentation.
      # @return [Object]
      def node_default_literal(node)
        case node&.type
        when :int, :float then node.children.first.to_s
        when :str then "'#{node.children.first}'"
        when :sym then ":#{node.children.first}"
        when :true then 'true' # rubocop:disable Lint/BooleanSymbol
        when :false then 'false' # rubocop:disable Lint/BooleanSymbol
        when :nil then 'nil'
        else node&.loc&.expression&.source
        end
      end

      # +Docscribe::InlineRewriter::DocBuilder.format_param_tag+ -> String
      #
      # Method documentation.
      #
      # @note module_function: when included, also defines #format_param_tag (instance visibility: private)
      # @param indent [Object] Param documentation.
      # @param pname [Object] Param documentation.
      # @param ty [Object] Param documentation.
      # @param description [Object] Param documentation.
      # @param style [Object] Param documentation.
      # @return [String]
      def format_param_tag(indent, pname, ty, description, style:)
        case style
        when 'type_name'
          "#{indent}# @param [#{ty}] #{pname} #{description}"
        else
          "#{indent}# @param #{pname} [#{ty}] #{description}"
        end
      end
    end
  end
end
