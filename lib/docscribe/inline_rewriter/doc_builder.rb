# frozen_string_literal: true

require 'docscribe/plugin'
require 'docscribe/infer'
require 'docscribe/inline_rewriter/source_helpers'

module Docscribe
  module InlineRewriter
    # Build generated YARD-style doc lines for methods and attribute helpers.
    #
    # DocBuilder combines:
    # - Ruby visibility/container metadata from Collector
    # - optional external signatures from Sorbet/RBS providers
    # - fallback AST inference from Docscribe::Infer
    #
    # It is responsible for producing complete doc blocks for aggressive mode
    # and "missing lines only" payloads for safe merge mode.
    module DocBuilder
      module_function

      # Build a complete doc block for one collected method insertion.
      #
      # External signatures, when available, override inferred param and return
      # types.
      #
      # @note module_function: when included, also defines #build (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [Docscribe::Config] config
      # @param [Object, nil] signature_provider provider responding to
      #   `signature_for(container:, scope:, name:)`
      # @param [nil] core_rbs_provider core RBS type lookup provider
      # @param [nil] param_types parameter name -> type map
      # @param [nil] return_type_override return type override string
      # @param [nil] override_tags hash of tags to override
      # @raise [StandardError]
      # @return [String, nil]
      def build(insertion, config:, signature_provider: nil, core_rbs_provider: nil, param_types: nil, return_type_override: nil, override_tags: nil)
        setup = doc_setup(insertion, config: config, signature_provider: signature_provider,
                                     core_rbs_provider: core_rbs_provider, param_types: param_types,
                                     return_type_override: return_type_override)
        return nil unless setup

        node = setup[:node]
        name = setup[:name]
        indent = setup[:indent]
        scope = setup[:scope]
        visibility = setup[:visibility]
        container = setup[:container]
        method_symbol = setup[:method_symbol]
        external_sig = setup[:external_sig]
        normal_type = setup[:normal_type]
        rescue_specs = setup[:rescue_specs]

        effective_param_types = param_types || build_param_types_from_node(node, external_sig: external_sig, config: config)
        params_lines = if config.emit_param_tags?
                         build_params_lines(node, indent, external_sig: external_sig, config: config,
                                                          param_types_override: effective_param_types)
                       end
        raise_types = config.emit_raise_tags? ? Docscribe::Infer.infer_raises_from_node(node) : []

        lines = []
        lines.concat(build_header_lines(indent, container, method_symbol, name, normal_type, config))
        lines.concat(build_default_msg_lines(indent, config, scope, visibility))
        lines.concat(build_visibility_tag_lines(indent, visibility, config))
        lines.concat(build_module_function_note_lines(indent, insertion, name))
        lines.concat(params_lines) if params_lines
        lines.concat(build_raise_tag_lines(indent, raise_types, config))

        ret_line = build_return_tag_line(indent, normal_type, config, scope, visibility)
        lines << ret_line if ret_line
        lines.concat(build_rescue_return_lines(indent, rescue_specs, config))
        lines.concat(build_plugin_tag_lines(insertion, indent, normal_type, override_tags))

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: name || '(unknown)', phase: 'DocBuilder.build')
        nil
      end

      # Build only the missing doc lines that should be merged into an existing
      # doc-like block.
      #
      # This is used by safe mode for non-destructive updates.
      #
      # @note module_function: when included, also defines #build_merge_additions (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [Array<String>] existing_lines
      # @param [Docscribe::Config] config
      # @param [Object, nil] signature_provider
      # @param [nil] core_rbs_provider core RBS type lookup provider
      # @param [nil] param_types parameter name -> type map
      # @param [nil] return_type_override return type override string
      # @raise [StandardError]
      # @return [String, nil]
      def build_merge_additions(insertion, existing_lines:, config:, signature_provider: nil, core_rbs_provider: nil,
                                param_types: nil, return_type_override: nil)
        setup = doc_setup(insertion, config: config, signature_provider: signature_provider,
                                     core_rbs_provider: core_rbs_provider, param_types: param_types,
                                     return_type_override: return_type_override)
        return '' unless setup

        name = setup[:name]
        indent = setup[:indent]
        scope = setup[:scope]
        visibility = setup[:visibility]
        external_sig = setup[:external_sig]
        normal_type = setup[:normal_type]
        rescue_specs = setup[:rescue_specs]
        node = setup[:node]

        info = parse_existing_doc_tags(existing_lines)

        lines = []
        lines << "#{indent}#" if existing_lines.any? && existing_lines.last.strip != '#'
        lines.concat(merge_visibility_tag_lines(indent, visibility, config, info))
        lines.concat(merge_module_function_note_lines(indent, insertion, name, info))
        lines.concat(merge_param_lines(node, indent, config, external_sig, param_types, info))
        lines.concat(merge_raise_tag_lines(node, indent, config, info))

        ret_line = merge_return_tag_line(indent, normal_type, config, scope, visibility, info)
        lines << ret_line if ret_line
        lines.concat(merge_rescue_return_lines(indent, rescue_specs, config, info))

        useful = lines.reject { |l| l.strip == '#' }
        return '' if useful.empty?

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: name || '(unknown)', phase: 'DocBuilder.build_merge_additions')
        nil
      end

      # Build structured missing-line information for safe merge mode.
      #
      # Returns both:
      # - generated missing lines
      # - structured reasons used by `--explain`
      #
      # @note module_function: when included, also defines #build_missing_merge_result (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [Array<String>] existing_lines
      # @param [Docscribe::Config] config
      # @param [Object, nil] signature_provider
      # @param [nil] core_rbs_provider core RBS type lookup provider
      # @param [nil] param_types parameter name -> type map
      # @param [nil] strategy rewrite strategy (:safe or :aggressive)
      # @param [nil] return_type_override return type override string
      # @param [nil] override_tags hash of tags to override
      # @raise [StandardError]
      # @return [Hash]
      def build_missing_merge_result(insertion, existing_lines:, config:, signature_provider: nil,
                                     core_rbs_provider: nil, param_types: nil, strategy: nil, return_type_override: nil, override_tags: nil)
        setup = doc_setup(insertion, config: config, signature_provider: signature_provider,
                                     core_rbs_provider: core_rbs_provider, param_types: param_types,
                                     return_type_override: return_type_override)
        return { lines: [], reasons: [] } unless setup

        name = setup[:name]
        indent = setup[:indent]
        scope = setup[:scope]
        visibility = setup[:visibility]
        external_sig = setup[:external_sig]
        normal_type = setup[:normal_type]
        rescue_specs = setup[:rescue_specs]
        node = setup[:node]

        info = parse_existing_doc_tags(existing_lines)

        lines = []
        reasons = []

        ctx = { node: node, indent: indent, config: config, external_sig: external_sig,
                info: info, strategy: strategy, scope: scope, visibility: visibility,
                normal_type: normal_type, rescue_specs: rescue_specs, insertion: insertion,
                param_types: param_types, override_tags: override_tags }
        collect_missing_visibility!(lines, reasons, **ctx)
        collect_missing_module_function_note!(lines, reasons, **ctx)
        collect_missing_params!(lines, reasons, **ctx)
        collect_missing_raises!(lines, reasons, **ctx)
        collect_missing_return!(lines, reasons, **ctx)
        collect_missing_rescue_returns!(lines, reasons, **ctx)
        collect_missing_plugin_tags!(lines, reasons, **ctx)

        { lines: lines, reasons: reasons }
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: name || '(unknown)', phase: 'DocBuilder.build_missing_merge_result')
        { lines: [], reasons: [] }
      end

      # Shared document setup extraction for all build methods.
      #
      # @note module_function: when included, also defines #doc_setup (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [Docscribe::Config] config
      # @param [Hash] opts additional options
      # @return [Hash, nil]
      def doc_setup(insertion, config:, **opts)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return nil unless name

        setup = extract_base_setup(insertion, name)
        external_sig = resolve_external_sig(setup[:container], setup[:scope], name, opts[:signature_provider])
        returns_spec = compute_returns_spec(node, config, opts[:param_types], opts[:core_rbs_provider])
        normal_type = opts[:return_type_override] || external_sig&.return_type || returns_spec[:normal]

        setup.merge(
          external_sig: external_sig,
          normal_type: normal_type,
          rescue_specs: returns_spec[:rescues] || []
        )
      end

      # Extract base node metadata.
      #
      # @note module_function: when included, also defines #extract_base_setup (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [String] name
      # @return [Hash]
      def extract_base_setup(insertion, name)
        n = insertion.node
        { node: n, name: name, indent: SourceHelpers.line_indent(n), scope: insertion.scope,
          visibility: insertion.visibility, container: insertion.container,
          method_symbol: insertion.scope == :instance ? '#' : '.' }
      end

      # Resolve external signature.
      #
      # @note module_function: when included, also defines #resolve_external_sig (instance visibility: private)
      # @param [String] container
      # @param [Symbol] scope
      # @param [String] name
      # @param [Object, nil] signature_provider
      # @return [Object, nil]
      def resolve_external_sig(container, scope, name, signature_provider)
        signature_provider&.signature_for(container: container, scope: scope, name: name)
      end

      # Compute returns_spec from node.
      #
      # @note module_function: when included, also defines #compute_returns_spec (instance visibility: private)
      # @param [Parser::AST::Node] node
      # @param [Docscribe::Config] config
      # @param [Hash, nil] param_types
      # @param [Object, nil] core_rbs_provider
      # @return [Hash]
      def compute_returns_spec(node, config, param_types, core_rbs_provider)
        Docscribe::Infer.returns_spec_from_node(
          node, fallback_type: config.fallback_type, nil_as_optional: config.nil_as_optional?,
                param_types: param_types, core_rbs_provider: core_rbs_provider
        )
      end

      # Parse existing doc comment lines and extract known YARD tags.
      #
      # Extracts: `@param` names, `@return`, `@raise`, `@private`, `@protected`,
      # `@module_function` notes, and `@option` lines.
      #
      # @note module_function: when included, also defines #parse_existing_doc_tags (instance visibility: private)
      # @param [Array<String>] lines existing doc comment lines
      # @return [Hash] parsed tag info
      def parse_existing_doc_tags(lines)
        param_names = {}
        param_types = {}
        has_return = false
        return_type = nil
        has_private = false
        has_protected = false
        has_module_function_note = false
        raise_types = {}
        plugin_tags = {}

        Array(lines).each do |line|
          if (m = line.match(/^\s*#\s*@(\w+)\b/))
            plugin_tags[m[1]] = true
          end
          if (pname = extract_param_name_from_param_line(line))
            param_names[pname] = true
            if (type_match = line.match(/@param\s+\[([^\]]+)\]\s+\S+/) || line.match(/@param\s+\S+\s+\[([^\]]+)\]/))
              param_types[pname] = type_match[1]
            end
          end

          if line.match?(/^\s*#\s*@return\b/)
            has_return = true
            if (m = line.match(/@return\s+\[([^\]]+)\]/))
              return_type = m[1]
            end
          end
          has_private ||= line.match?(/^\s*#\s*@private\b/)
          has_protected ||= line.match?(/^\s*#\s*@protected\b/)
          has_module_function_note ||= line.match?(/^\s*#\s*@note\s+module_function:/)

          extract_raise_types_from_line(line).each { |t| raise_types[t] = true }
        end

        {
          param_names: param_names,
          param_types: param_types,
          has_return: has_return,
          return_type: return_type,
          raise_types: raise_types,
          has_private: has_private,
          has_protected: has_protected,
          has_module_function_note: has_module_function_note,
          plugin_tags: plugin_tags
        }
      end

      # Extract exception names from a `@raise` doc line.
      #
      # @note module_function: when included, also defines #extract_raise_types_from_line (instance visibility: private)
      # @param [String] line a `@raise` doc line
      # @raise [StandardError]
      # @return [String, nil] the exception name or nil
      # @return [Array] if StandardError or line not matched
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

      # Parse exception names from a `@raise [ExceptionA, ExceptionB]` line.
      #
      # @note module_function: when included, also defines #parse_raise_bracket_list (instance visibility: private)
      # @param [String] s the `@raise` line text
      # @return [Array<String>, nil] the exception names or nil
      def parse_raise_bracket_list(str)
        str.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      # Build a param name => type map from a method node.
      #
      # @note module_function: when included, also defines #build_param_types_from_node (instance visibility: private)
      # @private
      # @param [Parser::AST::Node] node def or defs node
      # @param [Object, nil] external_sig external signature if available
      # @param [Docscribe::Config] config
      # @return [Hash{String => String}, nil]
      def build_param_types_from_node(node, external_sig:, config:)
        return nil unless node

        args = extract_args_from_node(node)
        return nil unless args

        param_types = {}

        (args.children || []).each do |a|
          case a.type
          when :arg
            collect_param_type(a, param_types, external_sig, config, infer_name: nil)
          when :optarg
            collect_optarg_param_type(a, param_types, external_sig, config, infer_name: nil)
          when :kwarg
            collect_param_type(a, param_types, external_sig, config, infer_name: ->(p) { "#{p}:" })
          when :kwoptarg
            collect_optarg_param_type(a, param_types, external_sig, config, infer_name: ->(p) { "#{p}:" })
          end
        end

        param_types.empty? ? nil : param_types
      end

      # Extract args sub-node from a def or defs node.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Parser::AST::Node] node
      # @return [Parser::AST::Node, nil]
      def extract_args_from_node(node)
        case node.type
        when :def then node.children[1]
        when :defs then node.children[2]
        end
      end

      # Collect param type for a required/keyword argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] param_types Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] config Param documentation.
      # @param [Object] infer_name Param documentation.
      # @return [Object]
      def collect_param_type(arg_node, param_types, external_sig, config, infer_name:)
        pname = arg_node.children.first.to_s
        infer_pname = infer_name ? infer_name.call(pname) : pname
        ty = external_sig&.param_types&.[](pname) ||
             Infer.infer_param_type(infer_pname, nil,
                                    fallback_type: config.fallback_type,
                                    treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?)
        param_types[pname] = ty
      end

      # Collect param type for an optional/keyword optional argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] param_types Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] config Param documentation.
      # @param [Object] infer_name Param documentation.
      # @return [Object]
      def collect_optarg_param_type(arg_node, param_types, external_sig, config, infer_name:)
        pname, default = *arg_node
        pname = pname.to_s
        infer_pname = infer_name ? infer_name.call(pname) : pname
        loc = default&.loc
        default_src = loc&.expression&.source
        ty = external_sig&.param_types&.[](pname) ||
             Infer.infer_param_type(infer_pname, default_src,
                                    fallback_type: config.fallback_type,
                                    treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?)
        param_types[pname] = ty
      end

      # Merge visibility tag lines for safe merge mode.
      #
      # @note module_function: when included, also defines #merge_visibility_tag_lines (instance visibility: private)
      # @param [String] indent
      # @param [Symbol] visibility
      # @param [Docscribe::Config] config
      # @param [Hash] info
      # @return [Array<String>]
      def merge_visibility_tag_lines(indent, visibility, config, info)
        return [] unless config.emit_visibility_tags?

        if visibility == :private && !info[:has_private]
          ["#{indent}# @private"]
        elsif visibility == :protected && !info[:has_protected]
          ["#{indent}# @protected"]
        else
          []
        end
      end

      # Merge module_function note line for safe merge mode.
      #
      # @note module_function: when included, also defines #merge_module_function_note_lines (instance visibility: private)
      # @param [String] indent
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [String] name
      # @param [Hash] info
      # @return [Array<String>]
      def merge_module_function_note_lines(indent, insertion, name, info)
        return [] unless insertion.respond_to?(:module_function) && insertion.module_function && !info[:has_module_function_note]

        included_vis = insertion.included_instance_visibility || :private
        ["#{indent}# @note module_function: when included, also defines ##{name} " \
         "(instance visibility: #{included_vis})"]
      end

      # Merge param lines for safe merge mode.
      #
      # @note module_function: when included, also defines #merge_param_lines (instance visibility: private)
      # @param [Parser::AST::Node] node
      # @param [String] indent
      # @param [Docscribe::Config] config
      # @param [Object, nil] external_sig
      # @param [Hash, nil] param_types
      # @param [Hash] info
      # @return [Array<String>]
      def merge_param_lines(node, indent, config, external_sig, param_types, info)
        return [] unless config.emit_param_tags?

        all_params = build_params_lines(node, indent, external_sig: external_sig, config: config, param_types_override: param_types)
        return [] unless all_params

        all_params.each_with_object([]) do |pl, result|
          pname = extract_param_name_from_param_line(pl)
          next if pname.nil? || info[:param_names].include?(pname)

          result << pl
        end
      end

      # Merge raise tag lines for safe merge mode.
      #
      # @note module_function: when included, also defines #merge_raise_tag_lines (instance visibility: private)
      # @param [Parser::AST::Node] node
      # @param [String] indent
      # @param [Docscribe::Config] config
      # @param [Hash] info
      # @return [Array<String>]
      def merge_raise_tag_lines(node, indent, config, info)
        return [] unless config.emit_raise_tags?

        inferred = Docscribe::Infer.infer_raises_from_node(node)
        existing = info[:raise_types] || {}
        inferred.reject { |rt| existing[rt] }
                .map { |rt| "#{indent}# @raise [#{rt}]" }
      end

      # Merge return tag line for safe merge mode.
      #
      # @note module_function: when included, also defines #merge_return_tag_line (instance visibility: private)
      # @param [String] indent
      # @param [String] normal_type
      # @param [Docscribe::Config] config
      # @param [Symbol] scope
      # @param [Symbol] visibility
      # @param [Hash] info
      # @return [String, nil]
      def merge_return_tag_line(indent, normal_type, config, scope, visibility, info)
        return unless config.emit_return_tag?(scope, visibility)
        return if info[:has_return]

        "#{indent}# @return [#{normal_type}]"
      end

      # Merge rescue conditional return lines for safe merge mode.
      #
      # @note module_function: when included, also defines #merge_rescue_return_lines (instance visibility: private)
      # @param [String] indent
      # @param [Array] rescue_specs
      # @param [Docscribe::Config] config
      # @param [Hash] info
      # @return [Array<String>]
      def merge_rescue_return_lines(indent, rescue_specs, config, info)
        return [] unless config.emit_rescue_conditional_returns?
        return [] if info[:has_return]

        rescue_specs.map do |exceptions, rtype|
          "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
        end
      end

      # Collect missing visibility tag for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_visibility! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_visibility!(lines, reasons, **ctx)
        return unless ctx[:config].emit_visibility_tags?

        if ctx[:visibility] == :private && !ctx[:info][:has_private]
          lines << "#{ctx[:indent]}# @private\n"
          reasons << { type: :missing_visibility, message: 'missing @private' }
        elsif ctx[:visibility] == :protected && !ctx[:info][:has_protected]
          lines << "#{ctx[:indent]}# @protected\n"
          reasons << { type: :missing_visibility, message: 'missing @protected' }
        end
      end

      # Collect missing module_function note for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_module_function_note! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_module_function_note!(lines, reasons, **ctx)
        insertion = ctx[:insertion]
        return unless insertion.respond_to?(:module_function) && insertion.module_function && !ctx[:info][:has_module_function_note]

        included_vis = insertion.included_instance_visibility || :private
        lines << "#{ctx[:indent]}# @note module_function: when included, also defines ##{ctx[:name]} " \
                 "(instance visibility: #{included_vis})\n"
        reasons << { type: :missing_module_function_note, message: 'missing module_function note' }
      end

      # Collect missing/updated param lines for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_params! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_params!(lines, reasons, **ctx)
        return unless ctx[:config].emit_param_tags?

        all_params = build_params_lines(ctx[:node], ctx[:indent], external_sig: ctx[:external_sig],
                                                                  config: ctx[:config], param_types_override: ctx[:param_types])
        return unless all_params

        all_params.each { |pl| collect_param_from_line(pl, lines, reasons, ctx) }
      end

      # Collect a single param line for build_missing_merge_result.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] pl Param documentation.
      # @param [Object] lines Param documentation.
      # @param [Object] reasons Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Object]
      def collect_param_from_line(param_line, lines, reasons, ctx)
        pname = extract_param_name_from_param_line(param_line)
        return unless pname

        if !ctx[:info][:param_names].include?(pname)
          lines << "#{param_line}\n"
          reasons << { type: :missing_param, message: "missing @param #{pname}", extra: { param: pname } }
        elsif ctx[:external_sig] && ctx[:info][:param_types][pname]
          collect_updated_param(param_line, pname, lines, reasons, ctx)
        end
      end

      # Collect an updated param line.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] pl Param documentation.
      # @param [Object] pname Param documentation.
      # @param [Object] lines Param documentation.
      # @param [Object] reasons Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [Object]
      def collect_updated_param(param_line, pname, lines, reasons, ctx)
        new_type = extract_param_type_from_param_line(param_line)
        return unless new_type && ctx[:info][:param_types][pname] != new_type

        lines << "#{param_line}\n" unless ctx[:strategy] == :safe
        reasons << {
          type: :updated_param,
          message: "updated @param #{pname} from #{ctx[:info][:param_types][pname]} to #{new_type}",
          extra: { param: pname }
        }
      end

      # Build generated `@param` / `@option` lines for a method node.
      #
      # External signatures take precedence over inferred parameter types.
      #
      # @note module_function: when included, also defines #build_params_lines (instance visibility: private)
      # @param [Parser::AST::Node] node
      # @param [String] indent
      # @param [Docscribe::Types::MethodSignature, nil] external_sig
      # @param [Docscribe::Config] config
      # @param [nil] param_types_override parameter name -> type map override
      # @return [Array<String>, nil]
      def build_params_lines(node, indent, external_sig:, config:, param_types_override: nil)
        fallback_type = config.fallback_type
        treat_options_keyword_as_hash = config.treat_options_keyword_as_hash?
        param_tag_style = config.param_tag_style
        param_documentation = config.include_param_documentation? ? config.param_documentation : ''

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
            params << build_arg_line(a, indent, external_sig, param_types_override,
                                     fallback_type, treat_options_keyword_as_hash,
                                     param_documentation, param_tag_style)
          when :optarg
            params.concat(build_optarg_lines(a, indent, external_sig, param_types_override,
                                             fallback_type, treat_options_keyword_as_hash,
                                             param_documentation, param_tag_style))
          when :kwarg
            params << build_kwarg_line(a, indent, external_sig, param_types_override,
                                       fallback_type, treat_options_keyword_as_hash,
                                       param_documentation, param_tag_style)
          when :kwoptarg
            params << build_kwoptarg_line(a, indent, external_sig, param_types_override,
                                          fallback_type, treat_options_keyword_as_hash,
                                          param_documentation, param_tag_style)
          when :restarg
            params << build_restarg_line(a, indent, external_sig, param_types_override,
                                         fallback_type, treat_options_keyword_as_hash,
                                         param_documentation, param_tag_style)
          when :kwrestarg
            params << build_kwrestarg_line(a, indent, external_sig, param_types_override,
                                           fallback_type, treat_options_keyword_as_hash,
                                           param_documentation, param_tag_style)
          when :blockarg
            params << build_blockarg_line(a, indent, external_sig, param_types_override,
                                          fallback_type, treat_options_keyword_as_hash,
                                          param_documentation, param_tag_style)
          when :forward_arg
            # skip
          end
        end

        params.empty? ? nil : params
      end

      # Build header line(s) for a doc block.
      #
      # @note module_function: when included, also defines #build_header_lines (instance visibility: private)
      # @param [String] indent
      # @param [String] container
      # @param [String] method_symbol
      # @param [String] name
      # @param [String] normal_type
      # @param [Docscribe::Config] config
      # @return [Array<String>]
      def build_header_lines(indent, container, method_symbol, name, normal_type, config)
        if config.emit_header?
          ["#{indent}# +#{container}#{method_symbol}#{name}+ -> #{normal_type}", "#{indent}#"]
        else
          []
        end
      end

      # Build default message lines for a doc block.
      #
      # @note module_function: when included, also defines #build_default_msg_lines (instance visibility: private)
      # @param [String] indent
      # @param [Docscribe::Config] config
      # @param [Symbol] scope
      # @param [Symbol] visibility
      # @return [Array<String>]
      def build_default_msg_lines(indent, config, scope, visibility)
        if config.include_default_message?
          ["#{indent}# #{config.default_message(scope, visibility)}", "#{indent}#"]
        else
          []
        end
      end

      # Build visibility tag line(s) for a full doc block.
      #
      # @note module_function: when included, also defines #build_visibility_tag_lines (instance visibility: private)
      # @param [String] indent
      # @param [Symbol] visibility
      # @param [Docscribe::Config] config
      # @return [Array<String>]
      def build_visibility_tag_lines(indent, visibility, config)
        return [] unless config.emit_visibility_tags?

        case visibility
        when :private then ["#{indent}# @private"]
        when :protected then ["#{indent}# @protected"]
        else []
        end
      end

      # Build module_function note line(s) for a full doc block.
      #
      # @note module_function: when included, also defines #build_module_function_note_lines (instance visibility: private)
      # @param [String] indent
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [String] name
      # @return [Array<String>]
      def build_module_function_note_lines(indent, insertion, name)
        return [] unless insertion.respond_to?(:module_function) && insertion.module_function

        included_vis =
          if insertion.respond_to?(:included_instance_visibility) && insertion.included_instance_visibility
            insertion.included_instance_visibility
          else
            :private
          end

        ["#{indent}# @note module_function: when included, also defines ##{name} " \
         "(instance visibility: #{included_vis})"]
      end

      # Build raise tag lines for a full doc block.
      #
      # @note module_function: when included, also defines #build_raise_tag_lines (instance visibility: private)
      # @param [String] indent
      # @param [Array<String>] raise_types
      # @param [Docscribe::Config] config
      # @return [Array<String>]
      def build_raise_tag_lines(indent, raise_types, config)
        return [] unless config.emit_raise_tags?

        raise_types.map { |rt| "#{indent}# @raise [#{rt}]" }
      end

      # Build return tag line for a full doc block.
      #
      # @note module_function: when included, also defines #build_return_tag_line (instance visibility: private)
      # @param [String] indent
      # @param [String] normal_type
      # @param [Docscribe::Config] config
      # @param [Symbol] scope
      # @param [Symbol] visibility
      # @return [String, nil]
      def build_return_tag_line(indent, normal_type, config, scope, visibility)
        return unless config.emit_return_tag?(scope, visibility)

        "#{indent}# @return [#{normal_type}]"
      end

      # Build rescue conditional return lines for a full doc block.
      #
      # @note module_function: when included, also defines #build_rescue_return_lines (instance visibility: private)
      # @param [String] indent
      # @param [Array] rescue_specs
      # @param [Docscribe::Config] config
      # @return [Array<String>]
      def build_rescue_return_lines(indent, rescue_specs, config)
        return [] unless config.emit_rescue_conditional_returns?

        rescue_specs.map do |exceptions, rtype|
          "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
        end
      end

      # Build plugin tag lines for a full doc block.
      #
      # @note module_function: when included, also defines #build_plugin_tag_lines (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [String] indent
      # @param [String] normal_type
      # @param [Array, nil] override_tags
      # @return [Array<String>]
      def build_plugin_tag_lines(insertion, indent, normal_type, override_tags)
        plugin_tags = Docscribe::Plugin.run_tag_plugins(build_plugin_context(insertion, normal_type: normal_type))
        plugin_tags.concat(Array(override_tags)) if override_tags
        render_plugin_tags(plugin_tags, indent)
      end

      # Build a param line for a required argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @param [Object] param_documentation Param documentation.
      # @param [Object] param_tag_style Param documentation.
      # @return [Object]
      def build_arg_line(arg_node, indent, external_sig, param_types_override, fallback_type, treat_options_keyword_as_hash, param_documentation, param_tag_style)
        pname = arg_node.children.first.to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, pname, nil,
                               fallback_type, treat_options_keyword_as_hash)
        format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)
      end

      # Build param lines for an optional argument (including @option lines).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @param [Object] param_documentation Param documentation.
      # @param [Object] param_tag_style Param documentation.
      # @return [Object]
      def build_optarg_lines(arg_node, indent, external_sig, param_types_override, fallback_type, treat_options_keyword_as_hash, param_documentation,
                             param_tag_style)
        pname, default = *arg_node
        pname = pname.to_s
        default_loc = default&.loc
        default_src = default_loc&.expression&.source
        ty = lookup_param_type(external_sig, param_types_override, pname, pname, default_src,
                               fallback_type, treat_options_keyword_as_hash)
        lines = [format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)]

        hash_option_pairs(default).each do |pair|
          lines << build_option_line(pair, indent, pname, fallback_type)
        end

        lines
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #hash_option_pairs (instance visibility: private)
      # @param [Object] node Param documentation.
      # @return [Object]
      def hash_option_pairs(node)
        return [] unless node&.type == :hash

        node.children.select { |child| child.is_a?(Parser::AST::Node) && child.type == :pair }
      end

      # Build an @option line from a hash pair node.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] pair Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] pname Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @return [Object]
      def build_option_line(pair, indent, pname, fallback_type)
        key_node, value_node = pair.children
        option_key = option_key_name(key_node)
        option_type = Infer::Literals.type_from_literal(value_node, fallback_type: fallback_type)
        option_default = node_default_literal(value_node)

        line = "#{indent}# @option #{pname} [#{option_type}] :#{option_key}"
        line += " (#{option_default})" if option_default
        line += ' Option documentation.'
        line
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #option_key_name (instance visibility: private)
      # @param [Object] key_node Param documentation.
      # @return [Object]
      def option_key_name(key_node)
        case key_node&.type
        when :sym, :str
          key_node.children.first.to_s
        else
          expression = key_node&.loc&.expression
          expression&.source.to_s.sub(/\A:/, '')
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #node_default_literal (instance visibility: private)
      # @param [Object] node Param documentation.
      # @return [Object]
      def node_default_literal(node)
        expression = node&.loc&.expression
        expression&.source
      end

      # Build a param line for a keyword argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @param [Object] param_documentation Param documentation.
      # @param [Object] param_tag_style Param documentation.
      # @return [Object]
      def build_kwarg_line(arg_node, indent, external_sig, param_types_override, fallback_type, treat_options_keyword_as_hash, param_documentation, param_tag_style)
        pname = arg_node.children.first.to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, "#{pname}:", nil,
                               fallback_type, treat_options_keyword_as_hash)
        format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)
      end

      # Build a param line for an optional keyword argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @param [Object] param_documentation Param documentation.
      # @param [Object] param_tag_style Param documentation.
      # @return [Object]
      def build_kwoptarg_line(arg_node, indent, external_sig, param_types_override, fallback_type, treat_options_keyword_as_hash, param_documentation,
                              param_tag_style)
        pname, default = *arg_node
        pname = pname.to_s
        default_loc = default&.loc
        default_src = default_loc&.expression&.source
        ty = lookup_param_type(external_sig, param_types_override, pname, "#{pname}:", default_src,
                               fallback_type, treat_options_keyword_as_hash)
        format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)
      end

      # Build a param line for a rest argument (*args).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @param [Object] param_documentation Param documentation.
      # @param [Object] param_tag_style Param documentation.
      # @return [Object]
      def build_restarg_line(arg_node, indent, external_sig, param_types_override, fallback_type, treat_options_keyword_as_hash, param_documentation,
                             param_tag_style)
        pname = (arg_node.children.first || 'args').to_s
        ty = if external_sig&.rest_positional&.element_type
               "Array<#{external_sig.rest_positional.element_type}>"
             else
               lookup_param_type_by_infer(param_types_override, pname, "*#{pname}",
                                          fallback_type, treat_options_keyword_as_hash)
             end
        format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)
      end

      # Build a param line for a keyword rest argument (**kwargs).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @param [Object] param_documentation Param documentation.
      # @param [Object] param_tag_style Param documentation.
      # @return [Object]
      def build_kwrestarg_line(arg_node, indent, external_sig, param_types_override, fallback_type, treat_options_keyword_as_hash, param_documentation,
                               param_tag_style)
        pname = (arg_node.children.first || 'kwargs').to_s
        ty = external_sig&.rest_keywords&.type ||
             lookup_param_type_by_infer(param_types_override, pname, "**#{pname}",
                                        fallback_type, treat_options_keyword_as_hash)
        format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)
      end

      # Build a param line for a block argument (&block).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] a Param documentation.
      # @param [Object] indent Param documentation.
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @param [Object] param_documentation Param documentation.
      # @param [Object] param_tag_style Param documentation.
      # @return [Object]
      def build_blockarg_line(arg_node, indent, external_sig, param_types_override, fallback_type, treat_options_keyword_as_hash, param_documentation,
                              param_tag_style)
        pname = (arg_node.children.first || 'block').to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, "&#{pname}", nil,
                               fallback_type, treat_options_keyword_as_hash)
        format_param_tag(indent, pname, ty, param_documentation, style: param_tag_style)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #format_param_tag (instance visibility: private)
      # @param [Object] indent Param documentation.
      # @param [Object] name Param documentation.
      # @param [Object] type Param documentation.
      # @param [Object] documentation Param documentation.
      # @param [Object] style Param documentation.
      # @return [Object]
      def format_param_tag(indent, name, type, documentation, style:)
        doc = documentation.to_s.strip
        type = type.to_s

        line = case style.to_s
               when 'name_type'
                 "#{indent}# @param #{name} [#{type}]"
               else
                 "#{indent}# @param [#{type}] #{name}"
               end

        doc.empty? ? line : "#{line} #{doc}"
      end

      # Three-tier type lookup: external_sig → override → inference.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] external_sig Param documentation.
      # @param [Object] param_types_override Param documentation.
      # @param [Object] pname Param documentation.
      # @param [Object] infer_name Param documentation.
      # @param [Object] infer_default Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @return [Object]
      def lookup_param_type(external_sig, param_types_override, pname, infer_name, infer_default, fallback_type, treat_options_keyword_as_hash)
        external_sig&.param_types&.[](pname) ||
          override_param_type_for(pname, param_types_override) ||
          Infer.infer_param_type(infer_name, infer_default,
                                 fallback_type: fallback_type,
                                 treat_options_keyword_as_hash: treat_options_keyword_as_hash)
      end

      # Two-tier type lookup: override → inference (for rest/kwrest types).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] param_types_override Param documentation.
      # @param [Object] pname Param documentation.
      # @param [Object] infer_name Param documentation.
      # @param [Object] fallback_type Param documentation.
      # @param [Object] treat_options_keyword_as_hash Param documentation.
      # @return [Object]
      def lookup_param_type_by_infer(param_types_override, pname, infer_name, fallback_type, treat_options_keyword_as_hash)
        override_param_type_for(pname, param_types_override) ||
          Infer.infer_param_type(infer_name, nil,
                                 fallback_type: fallback_type,
                                 treat_options_keyword_as_hash: treat_options_keyword_as_hash)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #override_param_type_for (instance visibility: private)
      # @param [Object] pname Param documentation.
      # @param [Object] override_map Param documentation.
      # @return [Object]
      def override_param_type_for(pname, override_map)
        return nil unless override_map

        key = pname.to_s
        override_map[key] || override_map[:"#{key}"] || override_map["#{key}:"] || override_map[:"#{key}:"]
      end

      # Extract the parameter name from a `@param` doc line.
      #
      # Handles both `"@param [Type] name"` and `"@param name [Type]"` styles.
      #
      # @note module_function: when included, also defines #extract_param_name_from_param_line (instance visibility: private)
      # @param [String] line a `@param` doc line
      # @return [String, nil] the parameter name or nil
      def extract_param_name_from_param_line(line)
        return Regexp.last_match(1) if line =~ /@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Extract the type from a `@param` tag line.
      #
      # @note module_function: when included, also defines #extract_param_type_from_param_line (instance visibility: private)
      # @param [String] line a `@param` tag line
      # @return [String, nil]
      def extract_param_type_from_param_line(line)
        if (m = line.match(/@param\s+\[([^\]]+)\]\s+\S+/) || line.match(/@param\s+\S+\s+\[([^\]]+)\]/))
          m[1]
        end
      end

      # Collect missing raise tags for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_raises! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_raises!(lines, reasons, **ctx)
        return unless ctx[:config].emit_raise_tags?

        inferred = Docscribe::Infer.infer_raises_from_node(ctx[:node])
        existing = ctx[:info][:raise_types] || {}
        missing = inferred.reject { |rt| existing[rt] }

        missing.each do |rt|
          lines << "#{ctx[:indent]}# @raise [#{rt}]\n"
          reasons << { type: :missing_raise, message: "missing @raise [#{rt}]", extra: { raise_type: rt } }
        end
      end

      # Collect missing/updated return tag for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_return! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_return!(lines, reasons, **ctx)
        return unless ctx[:config].emit_return_tag?(ctx[:scope], ctx[:visibility])

        if !ctx[:info][:has_return]
          lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n"
          reasons << { type: :missing_return, message: 'missing @return' }
        elsif ctx[:external_sig] && ctx[:info][:return_type] && ctx[:info][:return_type] != ctx[:normal_type]
          lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n" unless ctx[:strategy] == :safe
          reasons << {
            type: :updated_return,
            message: "updated @return from #{ctx[:info][:return_type]} to #{ctx[:normal_type]}"
          }
        end
      end

      # Collect missing rescue conditional returns for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_rescue_returns! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_rescue_returns!(lines, reasons, **ctx)
        return unless ctx[:config].emit_rescue_conditional_returns?
        return if ctx[:info][:has_return]

        ctx[:rescue_specs].each do |exceptions, rtype|
          lines << "#{ctx[:indent]}# @return [#{rtype}] if #{exceptions.join(', ')}\n"
          reasons << {
            type: :missing_return,
            message: "missing conditional @return for #{exceptions.join(', ')}"
          }
        end
      end

      # Collect missing plugin tags for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_plugin_tags! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_plugin_tags!(lines, reasons, **ctx)
        plugin_tags = Docscribe::Plugin.run_tag_plugins(build_plugin_context(ctx[:insertion], normal_type: ctx[:normal_type]))
        plugin_tags.concat(Array(ctx[:override_tags])) if ctx[:override_tags]

        plugin_tags.each do |tag|
          next if ctx[:info][:plugin_tags]&.[](tag.name)

          rendered = render_plugin_tags([tag], ctx[:indent]).first
          lines << "#{rendered}\n"
          reasons << { type: :missing_plugin_tag, message: "missing @#{tag.name}" }
        end
      end

      # Print a debug warning for a failed doc build phase.
      #
      # @note module_function: when included, also defines #debug_warn (instance visibility: private)
      # @param [StandardError] error the error that occurred
      # @param [Collector::Insertion] insertion the method insertion being processed
      # @param [String] name the method name
      # @param [String] phase the processing phase
      # @return [void]
      def debug_warn(error, insertion:, name:, phase:)
        return unless debug?

        node = insertion&.node
        expression = node&.loc&.expression
        buf_name = expression&.source_buffer&.name || '(unknown)'
        line = expression&.line
        scope = insertion&.scope
        method_symbol = scope == :class ? '.' : '#'
        container = insertion&.container || 'Object'

        where = +buf_name.to_s
        where << ":#{line}" if line
        where << " #{container}#{method_symbol}#{name}"

        warn "Docscribe DEBUG: #{phase} failed at #{where}: #{error.class}: #{error.message}"
      end

      # Check whether debug mode is enabled.
      #
      # @note module_function: when included, also defines #debug? (instance visibility: private)
      # @return [Boolean]
      def debug?
        ENV['DOCSCRIBE_DEBUG'] == '1'
      end

      # Build a Plugin::Context from a collected insertion.
      #
      # @note module_function
      # @note module_function: when included, also defines #build_plugin_context (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [String] normal_type resolved return type
      # @raise [StandardError]
      # @return [Docscribe::Plugin::Context]
      def build_plugin_context(insertion, normal_type:)
        node = insertion.node
        source = begin
          node.loc.expression.source
        rescue StandardError
          ''
        end

        Docscribe::Plugin::Context.new(
          node: node,
          container: insertion.container,
          scope: insertion.scope,
          visibility: insertion.visibility,
          method_name: SourceHelpers.node_name(node),
          inferred_params: {},
          inferred_return: normal_type,
          source: source
        )
      end

      # Render plugin tags as indented comment lines.
      #
      # @note module_function
      # @note module_function: when included, also defines #render_plugin_tags (instance visibility: private)
      # @param [Array<Docscribe::Plugin::Tag>] tags
      # @param [String] indent
      # @return [Array<String>]
      def render_plugin_tags(tags, indent)
        tags.map do |tag|
          type_part = tag.types&.any? ? " [#{tag.types.join(', ')}]" : ''
          text_part = tag.text ? " #{tag.text}" : ''
          "#{indent}# @#{tag.name}#{type_part}#{text_part}"
        end
      end
    end
  end
end
