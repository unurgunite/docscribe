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

      PARAM_TYPE_COLLECTORS = {
        arg: lambda { |arg_node, param_types, external_sig, config|
          collect_param_type(
            arg_node,
            param_types,
            external_sig,
            config,
            infer_name: nil
          )
        },

        optarg: lambda { |arg_node, param_types, external_sig, config|
          collect_optarg_param_type(
            arg_node,
            param_types,
            external_sig,
            config,
            infer_name: nil
          )
        },

        kwarg: lambda { |arg_node, param_types, external_sig, config|
          collect_param_type(
            arg_node,
            param_types,
            external_sig,
            config,
            infer_name: ->(param_name) { "#{param_name}:" }
          )
        },

        kwoptarg: lambda { |arg_node, param_types, external_sig, config|
          collect_optarg_param_type(
            arg_node,
            param_types,
            external_sig,
            config,
            infer_name: ->(param_name) { "#{param_name}:" }
          )
        }
      }.freeze

      PARAM_BUILDERS = {
        arg: lambda { |arg_node, indent, external_sig, param_types_override, **opts|
          [build_arg_line(arg_node, indent, external_sig, param_types_override, **opts)]
        },
        optarg: lambda { |arg_node, indent, external_sig, param_types_override, **opts|
          build_optarg_lines(arg_node, indent, external_sig, param_types_override, **opts)
        },
        kwarg: lambda { |arg_node, indent, external_sig, param_types_override, **opts|
          [build_kwarg_line(arg_node, indent, external_sig, param_types_override, **opts)]
        },
        kwoptarg: lambda { |arg_node, indent, external_sig, param_types_override, **opts|
          [build_kwoptarg_line(arg_node, indent, external_sig, param_types_override, **opts)]
        },
        restarg: lambda { |arg_node, indent, external_sig, param_types_override, **opts|
          [build_restarg_line(arg_node, indent, external_sig, param_types_override, **opts)]
        },
        kwrestarg: lambda { |arg_node, indent, external_sig, param_types_override, **opts|
          [build_kwrestarg_line(arg_node, indent, external_sig, param_types_override, **opts)]
        },
        blockarg: lambda { |arg_node, indent, external_sig, param_types_override, **opts|
          [build_blockarg_line(arg_node, indent, external_sig, param_types_override, **opts)]
        },
        forward_arg: ->(*) { [] } #: Array[String]
      }.freeze

      # Method documentation.
      #
      # @note module_function: when included, also defines #build (instance visibility: private)
      # @raise [StandardError]
      # @param [Object] insertion Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object] opts additional keyword options forwarded to doc_setup
      # @return [String, nil] if StandardError
      # @return [nil] if StandardError
      def build(insertion, config:, **opts)
        setup = doc_setup(insertion, config: config, **opts)
        return nil unless setup

        build_unsafe(insertion, config: config, setup: setup, **opts)
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: '(unknown)', phase: 'DocBuilder.build')
        nil
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_merge_additions (instance visibility: private)
      # @raise [StandardError]
      # @param [Object] insertion Param documentation.
      # @param [Array<String>] existing_lines Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object] options additional keyword options forwarded to downstream methods
      # @return [String, nil] if StandardError
      # @return [nil] if StandardError
      def build_merge_additions(insertion, existing_lines:, config:, **options)
        setup = doc_setup(insertion, config: config, **options)
        return '' unless setup

        info = parse_existing_doc_tags(existing_lines)
        merge_dest_lines(existing_lines, setup: setup, insertion: insertion, config: config, info: info,
                                         param_types: options[:param_types])
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: setup&.dig(:name) || '(unknown)',
                      phase: 'DocBuilder.build_merge_additions')
        nil
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_missing_merge_result (instance visibility: private)
      # @raise [StandardError]
      # @param [Object] insertion Param documentation.
      # @param [Array<String>] existing_lines Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object] options additional keyword options forwarded to downstream methods
      # @return [Hash<Symbol, Object>] if StandardError
      # @return [Hash] if StandardError
      def build_missing_merge_result(insertion, existing_lines:, config:, **options)
        setup = doc_setup(insertion, config: config, **options)
        return { lines: [], reasons: [] } unless setup

        info = parse_existing_doc_tags(existing_lines)
        collect_all_missing(setup, info, insertion, config, options)
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: setup&.dig(:name) || '(unknown)',
                      phase: 'DocBuilder.build_missing_merge_result')
        { lines: [], reasons: [] }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #doc_setup (instance visibility: private)
      # @param [Object] insertion Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object] opts additional options
      # @return [Hash<Symbol, Object>, nil]
      def doc_setup(insertion, config:, **opts)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return nil unless name

        setup = extract_base_setup(insertion, name)
        resolve_doc_setup!(setup, node, name, config, opts)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_unsafe (instance visibility: private)
      # @param [Object] insertion Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] setup Param documentation.
      # @param [Object] opts Param documentation.
      # @return [String]
      def build_unsafe(insertion, config:, setup:, **opts)
        _, pl, rt = build_param_and_raise_info(setup, config, opts)
        lines = build_doc_lines(setup, config: config, insertion: insertion, params_lines: pl, raise_types: rt,
                                       override_tags: opts[:override_tags],
                                       return_description: opts[:return_description],
                                       description: opts[:description])
        lines.map { |l| "#{l}\n" }.join
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_param_and_raise_info (instance visibility: private)
      # @param [Hash<Symbol, Object>] setup Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] opts Param documentation.
      # @return [Array<Object>]
      def build_param_and_raise_info(setup, config, opts)
        pt = opts[:param_types] || build_param_types_from_node(setup[:node], external_sig: setup[:external_sig],
                                                                             config: config)
        pl = if config.emit_param_tags?
               build_params_lines(setup[:node], setup[:indent], external_sig: setup[:external_sig], config: config,
                                                                param_types_override: pt,
                                                                param_descriptions: opts[:param_descriptions])
             end
        rt = config.emit_raise_tags? ? Docscribe::Infer.infer_raises_from_node(setup[:node]) : [] #: Array[String]
        [pt, pl, rt]
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #resolve_doc_setup! (instance visibility: private)
      # @param [Hash<Symbol, Object>] setup Param documentation.
      # @param [Parser::AST::Node] node Param documentation.
      # @param [String] name Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] opts Param documentation.
      # @return [Hash<Symbol, Object>]
      def resolve_doc_setup!(setup, node, name, config, opts)
        external_sig = resolve_external_sig(setup[:container], setup[:scope], name, opts[:signature_provider])
        returns_spec = compute_returns_spec(node, config, opts[:param_types], opts[:core_rbs_provider])
        normal_type = opts[:return_type_override] || external_sig&.return_type || returns_spec[:normal]

        setup.merge(
          external_sig: external_sig,
          normal_type: normal_type,
          rescue_specs: returns_spec[:rescues] || []
        )
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_base_setup (instance visibility: private)
      # @param [Object] insertion Param documentation.
      # @param [String] name Param documentation.
      # @return [Hash<Symbol, Object>]
      def extract_base_setup(insertion, name)
        n = insertion.node
        { node: n, name: name, indent: SourceHelpers.line_indent(n), scope: insertion.scope,
          visibility: insertion.visibility, container: insertion.container,
          method_symbol: insertion.scope == :instance ? '#' : '.' }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #resolve_external_sig (instance visibility: private)
      # @param [String] container Param documentation.
      # @param [Symbol] scope Param documentation.
      # @param [String] name Param documentation.
      # @param [Object, nil] signature_provider Param documentation.
      # @return [Object, nil]
      def resolve_external_sig(container, scope, name, signature_provider)
        signature_provider&.signature_for(container: container, scope: scope, name: name)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #compute_returns_spec (instance visibility: private)
      # @param [Parser::AST::Node] node Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<String, String>, nil] param_types Param documentation.
      # @param [Object, nil] core_rbs_provider Param documentation.
      # @return [Hash<Symbol, Object>]
      def compute_returns_spec(node, config, param_types, core_rbs_provider)
        Docscribe::Infer.returns_spec_from_node(
          node, fallback_type: config.fallback_type, nil_as_optional: config.nil_as_optional?,
                param_types: param_types, core_rbs_provider: core_rbs_provider
        )
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #parse_existing_doc_tags (instance visibility: private)
      # @param [Array<String>] lines existing doc comment lines
      # @return [Hash<Symbol, Object>] parsed tag info
      def parse_existing_doc_tags(lines)
        init = init_parse_info
        tags_started = false
        Array(lines).each_with_object(init) do |line, info|
          extract_param_info(line, info[:param_names], info[:param_types], info[:param_descriptions])
          extract_return_info(line, info)
          extract_visibility_info(line, info)
          extract_raise_info(line, info[:raise_types])
          extract_plugin_info(line, info[:plugin_tags])

          content = line.sub(/^\s*#\s*/, '').rstrip
          tags_started = true if content.start_with?('@')
          info[:description] << content unless tags_started
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #init_parse_info (instance visibility: private)
      # @return [Hash<Symbol, Object>]
      def init_parse_info
        {
          param_names: {}, param_types: {}, param_descriptions: {},
          raise_types: {}, plugin_tags: {},
          has_return: false, return_type: nil, return_description: nil,
          has_private: false, has_protected: false, has_module_function_note: false,
          description: []
        }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_dest_lines (instance visibility: private)
      # @param [Array<String>] existing_lines existing doc comment lines to merge into
      # @param [Object] ctx merge context hash (setup, insertion, config, info, param_types)
      # @return [String, nil]
      def merge_dest_lines(existing_lines, **ctx)
        merge_lines_with_context(existing_lines, **ctx)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_lines_with_context (instance visibility: private)
      # @param [Array<String>] existing_lines existing doc comment lines being merged
      # @param [Object] ctx merge context (setup, insertion, config, info, param_types)
      # @return [String]
      def merge_lines_with_context(existing_lines, **ctx)
        s = ctx[:setup]
        i = s[:indent]
        config = ctx[:config]
        info = ctx[:info]
        base_ary = build_initial_line_ary(existing_lines, i)
        line_ary = merge_all_tag_lines(base_ary, s: s, i: i, config: config, info: info,
                                                 insertion: ctx[:insertion], param_types: ctx[:param_types])
        useful = line_ary.reject { |l| l.strip == '#' }
        return '' if useful.empty?

        line_ary.map { |l| "#{l}\n" }.join
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_initial_line_ary (instance visibility: private)
      # @param [Array<String>] existing_lines Param documentation.
      # @param [String] indent Param documentation.
      # @return [Array<String>]
      def build_initial_line_ary(existing_lines, indent)
        existing_lines.any? && existing_lines.last.strip != '#' ? ["#{indent}#"] : []
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_all_tag_lines (instance visibility: private)
      # @param [Array<String>] base_ary Param documentation.
      # @param [Object] ctx context hash with setup, config, info, insertion, param_types
      # @return [Array<String>]
      def merge_all_tag_lines(base_ary, **ctx)
        line_ary = base_ary.dup
        merge_tag_lines_core(line_ary, ctx)
        line_ary.concat(merge_rescue_return_lines(ctx[:i], ctx[:s][:rescue_specs], ctx[:config], ctx[:info]))
        line_ary
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_tag_lines_core (instance visibility: private)
      # @param [Array<String>] line_ary Param documentation.
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [void]
      def merge_tag_lines_core(line_ary, ctx)
        append_merge_tag_lines(line_ary, ctx)
        merge_return_line(line_ary, ctx[:i], ctx[:s], ctx[:config], ctx[:info])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #append_merge_tag_lines (instance visibility: private)
      # @param [Array<String>] line_ary Param documentation.
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [void]
      def append_merge_tag_lines(line_ary, ctx)
        line_ary.concat(build_all_merge_tags(ctx))
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_all_merge_tags (instance visibility: private)
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [Array<String>]
      def build_all_merge_tags(ctx)
        i = ctx[:i]
        s = ctx[:s]
        c = ctx[:config]
        info = ctx[:info]
        [merge_visibility_tag_lines(i, s[:visibility], c, info),
         merge_module_function_note_lines(i, ctx[:insertion], s[:name], info),
         merge_param_lines(s[:node], i, config: c, external_sig: s[:external_sig],
                                        param_types: ctx[:param_types], info: info),
         merge_raise_tag_lines(s[:node], i, c, info)].flatten
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_return_line (instance visibility: private)
      # @param [Array<String>] line_ary Param documentation.
      # @param [String] indent indentation string for doc comment lines
      # @param [Hash<Symbol, Object>] setup method setup hash with node, name, types, scope
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] info Param documentation.
      # @return [void]
      def merge_return_line(line_ary, indent, setup, config, info)
        emit_ret = config.emit_return_tag?(setup[:scope], setup[:visibility])
        ret_line = merge_return_tag_line(indent, setup[:normal_type], config: config, scope: setup[:scope],
                                                                      visibility: setup[:visibility], info: info)

        line_ary << ret_line if emit_ret && ret_line
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_all_missing (instance visibility: private)
      # @param [Hash<Symbol, Object>] setup resolved setup hash with node, name, indent, types
      # @param [Hash<Symbol, Object>] info parsed existing doc tag information
      # @param [Object] insertion the collected method insertion object
      # @param [Docscribe::Config] config Docscribe configuration object
      # @param [Hash<Symbol, Object>] options additional options hash forwarded to missing collector
      # @return [Hash<Symbol, Object>]
      def collect_all_missing(setup, info, insertion, config, options)
        s = setup
        ctx = { node: s[:node], indent: s[:indent], config: config, external_sig: s[:external_sig],
                info: info, strategy: options[:strategy], scope: s[:scope], visibility: s[:visibility],
                normal_type: s[:normal_type], rescue_specs: s[:rescue_specs], insertion: insertion,
                param_types: options[:param_types], override_tags: options[:override_tags] }
        collect_missing_all(ctx)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_missing_all (instance visibility: private)
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [Hash<Symbol, Object>]
      def collect_missing_all(ctx)
        lines = [] #: Array[String]
        reasons = [] #: Array[Hash]
        collect_missing_visibility!(lines, reasons, **ctx)
        collect_missing_module_function_note!(lines, reasons, **ctx)
        collect_missing_params!(lines, reasons, **ctx)
        collect_missing_raises!(lines, reasons, **ctx)
        collect_missing_return!(lines, reasons, **ctx)
        collect_missing_rescue_returns!(lines, reasons, **ctx)
        collect_missing_plugin_tags!(lines, reasons, **ctx)
        { lines: lines, reasons: reasons }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_param_info (instance visibility: private)
      # @param [String] line a single doc comment line to parse
      # @param [Hash<String, Object>] param_names hash tracking existing @param names
      # @param [Hash<String, String>] param_types hash tracking existing @param types
      # @param [nil] param_descriptions Param documentation.
      # @return [void]
      def extract_param_info(line, param_names, param_types, param_descriptions = nil)
        return unless (pname = extract_param_name_from_param_line(line))

        param_names[pname] = true
        unless (type_match = line.match(/@param\s+\[([^\]]+)\]\s+\S+/) || line.match(/@param\s+\S+\s+\[([^\]]+)\]/))
          return
        end

        param_types[pname] = type_match[1] || 'untyped'
        return unless param_descriptions

        desc = extract_param_description(line)
        param_descriptions[pname] = desc if desc
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_return_info (instance visibility: private)
      # @param [String] line a single doc comment line to parse
      # @param [Hash<Symbol, Object>] info parse info hash to update with return data
      # @return [void]
      def extract_return_info(line, info)
        return unless line.match?(/^\s*#\s*@return\b/)

        info[:has_return] = true
        if (m = line.match(/@return\s+\[([^\]]+)\](?:\s+(.*))?/))
          info[:return_type] = m[1]
          info[:return_description] = m[2]&.strip
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_visibility_info (instance visibility: private)
      # @param [String] line a single doc comment line to parse
      # @param [Hash<Symbol, Object>] info parse info hash to update with visibility flags
      # @return [void]
      def extract_visibility_info(line, info)
        info[:has_private] ||= line.match?(/^\s*#\s*@private\b/)
        info[:has_protected] ||= line.match?(/^\s*#\s*@protected\b/)
        info[:has_module_function_note] ||= line.match?(/^\s*#\s*@note\s+module_function:/)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_raise_info (instance visibility: private)
      # @param [String] line a single doc comment line to parse
      # @param [Hash<String, Object>] raise_types hash tracking existing @raise types
      # @return [void]
      def extract_raise_info(line, raise_types)
        extract_raise_types_from_line(line).each { |t| raise_types[t || ''] = true }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_plugin_info (instance visibility: private)
      # @param [String] line a single doc comment line to parse
      # @param [Hash<String, Object>] plugin_tags hash tracking existing plugin tag names
      # @return [nil, Object]
      def extract_plugin_info(line, plugin_tags)
        return unless (m = line.match(/^\s*#\s*@(\w+)\b/))

        plugin_tags[m[1] || ''] = true
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_raise_types_from_line (instance visibility: private)
      # @raise [StandardError]
      # @param [String] line a `@raise` doc line
      # @return [Array<String, nil>] if StandardError
      # @return [Array] if StandardError
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #parse_raise_bracket_list (instance visibility: private)
      # @param [String] str comma-separated exception names string from @raise brackets
      # @return [Array<String>] the exception names or nil
      def parse_raise_bracket_list(str)
        str.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_param_types_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node def or defs node
      # @param [Object, nil] external_sig external signature if available
      # @param [Docscribe::Config] config Param documentation.
      # @return [Hash<String, String>, nil]
      def build_param_types_from_node(node, external_sig:, config:)
        return unless node

        args = extract_args_from_node(node)
        return unless args

        param_types = {} #: Hash[String, String]
        collect_all_param_types(args, param_types, external_sig, config)
        param_types.empty? ? nil : param_types
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_all_param_types (instance visibility: private)
      # @param [Object] args Param documentation.
      # @param [Hash<String, String>] param_types Param documentation.
      # @param [Object, nil] external_sig Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @return [void]
      def collect_all_param_types(args, param_types, external_sig, config)
        (args.children || []).each do |a|
          collector = PARAM_TYPE_COLLECTORS[a.type]
          collector&.call(a, param_types, external_sig, config)
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_param_type (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the required/keyword argument
      # @param [Hash<String, String>] param_types hash accumulating parameter name-to-type mappings
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Docscribe::Config] config Docscribe configuration for fallback type options
      # @param [Proc, nil] infer_name lambda to transform parameter name for inference
      # @return [void]
      def collect_param_type(arg_node, param_types, external_sig, config, infer_name:)
        pname = arg_node.children.first.to_s
        infer_pname = resolve_infer_name(pname, infer_name)
        ty = external_sig&.param_types&.[](pname) ||
             Infer.infer_param_type(infer_pname, nil,
                                    fallback_type: config.fallback_type,
                                    treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?)
        param_types[pname] = ty
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_optarg_param_type (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the optional/keyword optional argument
      # @param [Hash<String, String>] param_types hash accumulating parameter name-to-type mappings
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Docscribe::Config] config Docscribe configuration for fallback type options
      # @param [Proc, nil] infer_name lambda to transform parameter name for inference
      # @return [void]
      def collect_optarg_param_type(arg_node, param_types, external_sig, config, infer_name:)
        pname, default = *arg_node
        pname = pname.to_s
        default_src = source_from_node(default)
        infer_pname = resolve_infer_name(pname, infer_name)
        ty = external_sig&.param_types&.[](pname) ||
             Infer.infer_param_type(infer_pname, default_src,
                                    fallback_type: config.fallback_type,
                                    treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?)
        param_types[pname] = ty
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_visibility_tag_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Symbol] visibility Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] info Param documentation.
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

      # Method documentation.
      #
      # @note module_function: when included, also defines
      #   #merge_module_function_note_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Object] insertion Param documentation.
      # @param [String] name Param documentation.
      # @param [Hash<Symbol, Object>] info Param documentation.
      # @return [Array<String>]
      def merge_module_function_note_lines(indent, insertion, name, info)
        unless insertion.respond_to?(:module_function) && insertion.module_function && !info[:has_module_function_note]
          return []
        end

        included_vis = insertion.included_instance_visibility || :private
        ["#{indent}# @note module_function: when included, also defines ##{name} " \
         "(instance visibility: #{included_vis})"]
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_param_lines (instance visibility: private)
      # @param [Parser::AST::Node] node Param documentation.
      # @param [String] indent Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object] opts additional options including external_sig, param_types, info
      # @return [Array<String>]
      def merge_param_lines(node, indent, config:, **opts)
        return [] unless config.emit_param_tags?

        all_params = build_params_lines(node, indent, external_sig: opts[:external_sig], config: config,
                                                      param_types_override: opts[:param_types])
        return [] unless all_params

        info = opts[:info]
        all_params.each_with_object([]) do |pl, result|
          pname = extract_param_name_from_param_line(pl)
          next if pname.nil? || info[:param_names].include?(pname)

          result << pl
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_raise_tag_lines (instance visibility: private)
      # @param [Parser::AST::Node] node Param documentation.
      # @param [String] indent Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] info Param documentation.
      # @return [Array<String>]
      def merge_raise_tag_lines(node, indent, config, info)
        return [] unless config.emit_raise_tags?

        inferred = Docscribe::Infer.infer_raises_from_node(node)
        existing = info[:raise_types] || {}
        inferred.reject { |rt| existing[rt] }
                .map { |rt| "#{indent}# @raise [#{rt}]" }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_return_tag_line (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [String] normal_type Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object] opts additional options including scope, visibility, info
      # @return [String, nil]
      def merge_return_tag_line(indent, normal_type, config:, **opts)
        return unless config.emit_return_tag?(opts[:scope], opts[:visibility])
        return if opts[:info][:has_return]

        "#{indent}# @return [#{normal_type}]"
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #merge_rescue_return_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Array<Object>] rescue_specs Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] info Param documentation.
      # @return [Array<String>]
      def merge_rescue_return_lines(indent, rescue_specs, config, info)
        return [] unless config.emit_rescue_conditional_returns?
        return [] if info[:has_return]

        rescue_specs.map do |exceptions, rtype|
          "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_missing_visibility! (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [void]
      def collect_missing_visibility!(lines, reasons, **ctx)
        return unless ctx[:config].emit_visibility_tags?

        add_missing_private(lines, reasons, ctx)
        add_missing_protected(lines, reasons, ctx)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #add_missing_private (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [void]
      def add_missing_private(lines, reasons, ctx)
        return unless ctx[:visibility] == :private && !ctx[:info][:has_private]

        lines << "#{ctx[:indent]}# @private\n"
        reasons << { type: :missing_visibility, message: 'missing @private' }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #add_missing_protected (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [void]
      def add_missing_protected(lines, reasons, ctx)
        return unless ctx[:visibility] == :protected && !ctx[:info][:has_protected]

        lines << "#{ctx[:indent]}# @protected\n"
        reasons << { type: :missing_visibility, message: 'missing @protected' }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines
      #   #collect_missing_module_function_note! (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [void]
      def collect_missing_module_function_note!(lines, reasons, **ctx)
        insertion = ctx[:insertion]
        unless insertion.respond_to?(:module_function) && insertion.module_function &&
               !ctx[:info][:has_module_function_note]
          return
        end

        included_vis = insertion.included_instance_visibility || :private
        lines << "#{ctx[:indent]}# @note module_function: when included, also defines ##{ctx[:name]} " \
                 "(instance visibility: #{included_vis})\n"
        reasons << { type: :missing_module_function_note, message: 'missing module_function note' }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_missing_params! (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [void]
      def collect_missing_params!(lines, reasons, **ctx)
        return unless ctx[:config].emit_param_tags?

        all_params = build_params_lines(ctx[:node], ctx[:indent],
                                        external_sig: ctx[:external_sig], config: ctx[:config],
                                        param_types_override: ctx[:param_types])
        return unless all_params

        all_params.each { |pl| collect_param_from_line(pl, lines, reasons, ctx) }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_param_from_line (instance visibility: private)
      # @param [String] param_line a single @param tag line to evaluate
      # @param [Array<String>] lines array of output doc lines being accumulated
      # @param [Array<Hash<Symbol, Object>>] reasons array of reason hashes for --explain output
      # @param [Hash<Symbol, Object>] ctx merged context hash with build parameters
      # @return [void]
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_updated_param (instance visibility: private)
      # @param [String] param_line a single @param tag line to evaluate
      # @param [String] pname the parameter name string
      # @param [Array<String>] lines array of output doc lines being accumulated
      # @param [Array<Hash<Symbol, Object>>] reasons array of reason hashes for --explain output
      # @param [Hash<Symbol, Object>] ctx merged context hash with build parameters
      # @return [void]
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_params_lines (instance visibility: private)
      # @param [Parser::AST::Node] node Param documentation.
      # @param [String] indent Param documentation.
      # @param [Object, nil] external_sig Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash] kwargs Param documentation.
      # @return [Array<String>, nil]
      def build_params_lines(node, indent, external_sig:, config:, **kwargs)
        args = extract_args_from_node(node)
        return nil unless args

        build_all_param_lines(args, indent, config, external_sig: external_sig, **kwargs)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_all_param_lines (instance visibility: private)
      # @param [Object] args Param documentation.
      # @param [String] indent Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object, nil] external_sig Param documentation.
      # @param [Object] kwargs Param documentation.
      # @return [Array<String>, nil]
      def build_all_param_lines(args, indent, config, external_sig: nil, **kwargs)
        default_pd = config.include_param_documentation? ? config.param_documentation : ''
        params = (args.children || []).each_with_object([]) do |a, p|
          pd = (kwargs[:param_descriptions] || {})[param_name_from_arg(a)] || default_pd
          p.concat(build_param_line(a, indent, external_sig, kwargs[:param_types_override],
                                    fallback_type: config.fallback_type,
                                    treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?,
                                    param_documentation: pd,
                                    param_tag_style: config.param_tag_style))
        end
        params.empty? ? nil : params
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_doc_lines (instance visibility: private)
      # @param [Hash<Symbol, Object>] setup method setup hash with indent, name, types, scope
      # @param [Docscribe::Config] config Docscribe configuration object
      # @param [Object] kwargs additional keyword args including insertion, params_lines, raise_types, override_tags
      # @return [Array<String>]
      def build_doc_lines(setup, config:, **kwargs)
        i = setup[:indent]
        assemble_doc_lines(i, setup, config: config, insertion: kwargs[:insertion],
                                     params_lines: kwargs[:params_lines],
                                     raise_types: kwargs[:raise_types], override_tags: kwargs[:override_tags],
                                     return_description: kwargs[:return_description],
                                     description: kwargs[:description])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #assemble_doc_lines (instance visibility: private)
      # @param [String] indent indent
      # @param [Hash<Symbol, Object>] setup setup
      # @param [Object] ctx context hash with config, insertion, params_lines, raise_types, override_tags
      # @return [Array<String>]
      def assemble_doc_lines(indent, setup, **ctx)
        line_ary = build_header_lines(
          indent,
          config: ctx[:config],
          container: setup[:container], method_symbol: setup[:method_symbol], name: setup[:name],
          normal_type: setup[:normal_type]
        )

        append_assemble_body_lines(line_ary, indent, setup, ctx)
        line_ary
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #append_assemble_body_lines (instance visibility: private)
      # @param [Array<String>] line_ary Param documentation.
      # @param [String] indent indentation string for doc comment lines
      # @param [Hash<Symbol, Object>] setup method setup hash with name, types, scope
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [void]
      def append_assemble_body_lines(line_ary, indent, setup, ctx)
        line_ary.concat(build_all_body_tags(indent, setup, ctx))
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_all_body_tags (instance visibility: private)
      # @param [String] indent indentation string for doc comment lines
      # @param [Hash<Symbol, Object>] setup method setup hash with name, types, scope
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [Array<String>]
      def build_all_body_tags(indent, setup, ctx)
        result = core_body_tags(indent, setup, ctx)
        result.insert(3, ctx[:params_lines]) if ctx[:params_lines]
        result.flatten
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #core_body_tags (instance visibility: private)
      # @param [String] indent indentation string for doc comment lines
      # @param [Hash<Symbol, Object>] setup method setup hash with name, types, scope
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [Array<Object>]
      def core_body_tags(indent, setup, ctx)
        config = ctx[:config]
        [
          defaults_and_visibility(indent, config, setup[:scope], setup[:visibility],
                                  description: ctx[:description]),
          build_module_function_note_lines(indent, ctx[:insertion], setup[:name]),
          build_raise_tag_lines(indent, ctx[:raise_types], config),
          build_return_line_if_needed(indent, setup, config, ctx),
          build_rescue_return_lines(indent, setup[:rescue_specs], config),
          build_plugin_tag_lines(ctx[:insertion], indent, setup[:normal_type], ctx[:override_tags])
        ]
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #defaults_and_visibility (instance visibility: private)
      # @param [String] indent indentation string for doc comment lines
      # @param [Docscribe::Config] config Param documentation.
      # @param [Symbol] scope Param documentation.
      # @param [Symbol] visibility Param documentation.
      # @param [nil] description Param documentation.
      # @return [Array<String>]
      def defaults_and_visibility(indent, config, scope, visibility, description: nil)
        [
          build_default_msg_lines(indent, config, scope, visibility, description: description),
          build_visibility_tag_lines(indent, visibility, config)
        ].flatten
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_return_line_if_needed (instance visibility: private)
      # @param [String] indent indentation string for doc comment lines
      # @param [Hash<Symbol, Object>] setup method setup hash with name, normal_type, scope, visibility
      # @param [Docscribe::Config] config Param documentation.
      # @param [Hash<Symbol, Object>] ctx Param documentation.
      # @return [Array<String>]
      def build_return_line_if_needed(indent, setup, config, ctx)
        ret_line = build_return_tag_line(indent, setup[:normal_type], config, setup[:scope], setup[:visibility])
        rd = ctx[:return_description]
        ret_line = "#{ret_line} #{rd}" if ret_line && rd && !rd.empty?
        ret_line ? [ret_line] : []
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_args_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node Param documentation.
      # @return [Parser::AST::Node, nil]
      def extract_args_from_node(node)
        case node.type
        when :def then node.children[1]
        when :defs then node.children[2]
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_param_line (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the argument
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting (fallback_type, param_tag_style, etc.)
      # @return [Array<String>]
      def build_param_line(arg_node, indent, external_sig, param_types_override, **opts)
        PARAM_BUILDERS.fetch(arg_node.type, lambda { |*|
          [] #: Array[String]
        }).call(arg_node, indent, external_sig, param_types_override, **opts)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_header_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Object] opts additional options including container, method_symbol, name, normal_type
      # @return [Array<String>]
      def build_header_lines(indent, config:, **opts)
        if config.emit_header?
          c = opts[:container]
          ms = opts[:method_symbol]
          n = opts[:name]
          nt = opts[:normal_type]
          ["#{indent}# +#{c}#{ms}#{n}+ -> #{nt}", "#{indent}#"]
        else
          []
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_default_msg_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Symbol] scope Param documentation.
      # @param [Symbol] visibility Param documentation.
      # @param [nil] description Param documentation.
      # @return [Array<String>]
      def build_default_msg_lines(indent, config, scope, visibility, description: nil)
        if description&.any?
          result = description.map { |line| line.empty? ? "#{indent}#" : "#{indent}# #{line}" }
          result << "#{indent}#" unless result.last == "#{indent}#"
          result
        elsif config.include_default_message?
          ["#{indent}# #{config.default_message(scope, visibility)}", "#{indent}#"]
        else
          []
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_visibility_tag_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Symbol] visibility Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @return [Array<String>]
      def build_visibility_tag_lines(indent, visibility, config)
        return [] unless config.emit_visibility_tags?

        case visibility
        when :private then ["#{indent}# @private"]
        when :protected then ["#{indent}# @protected"]
        else []
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines
      #   #build_module_function_note_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Object] insertion Param documentation.
      # @param [String] name Param documentation.
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_raise_tag_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Array<String>] raise_types Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @return [Array<String>]
      def build_raise_tag_lines(indent, raise_types, config)
        return [] unless config.emit_raise_tags?

        raise_types.map { |rt| "#{indent}# @raise [#{rt}]" }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_return_tag_line (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [String] normal_type Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @param [Symbol] scope Param documentation.
      # @param [Symbol] visibility Param documentation.
      # @return [String, nil]
      def build_return_tag_line(indent, normal_type, config, scope, visibility)
        return unless config.emit_return_tag?(scope, visibility)

        "#{indent}# @return [#{normal_type}]"
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_rescue_return_lines (instance visibility: private)
      # @param [String] indent Param documentation.
      # @param [Array<Object>] rescue_specs Param documentation.
      # @param [Docscribe::Config] config Param documentation.
      # @return [Array<String>]
      def build_rescue_return_lines(indent, rescue_specs, config)
        return [] unless config.emit_rescue_conditional_returns?

        rescue_specs.map do |exceptions, rtype|
          "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_plugin_tag_lines (instance visibility: private)
      # @param [Object] insertion Param documentation.
      # @param [String] indent Param documentation.
      # @param [String] normal_type Param documentation.
      # @param [Array<Object>, nil] override_tags Param documentation.
      # @return [Array<String>]
      def build_plugin_tag_lines(insertion, indent, normal_type, override_tags)
        plugin_tags = Docscribe::Plugin.run_tag_plugins(build_plugin_context(insertion, normal_type: normal_type))
        plugin_tags.concat(Array(override_tags)) if override_tags
        render_plugin_tags(plugin_tags, indent)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_arg_line (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the required argument
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting
      # @return [String]
      def build_arg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = arg_node.children.first.to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, pname,
                               infer_default: nil,
                               fallback_type: opts[:fallback_type],
                               treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_optarg_lines (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the optional argument
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting
      # @return [Array<String>]
      def build_optarg_lines(arg_node, indent, external_sig, param_types_override, **opts)
        pname, default = *arg_node
        pname = pname.to_s
        ty = optarg_type(pname, default, external_sig, param_types_override, opts)
        lines = [format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])]

        append_option_lines(lines, default, indent, pname, opts[:fallback_type])
        lines
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #optarg_type (instance visibility: private)
      # @param [String] pname Param documentation.
      # @param [Object] default Param documentation.
      # @param [Object, nil] external_sig Param documentation.
      # @param [Hash<String, String>, nil] param_types_override Param documentation.
      # @param [Hash<Symbol, Object>] opts Param documentation.
      # @return [String]
      def optarg_type(pname, default, external_sig, param_types_override, opts)
        default_src = source_from_node(default)
        lookup_param_type(external_sig, param_types_override, pname, pname,
                          infer_default: default_src,
                          fallback_type: opts[:fallback_type],
                          treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #source_from_node (instance visibility: private)
      # @param [Parser::AST::Node] node Param documentation.
      # @return [String, nil]
      def source_from_node(node)
        loc = node&.loc
        loc&.expression&.source
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #resolve_infer_name (instance visibility: private)
      # @param [String] pname Param documentation.
      # @param [Proc, nil] infer_name Param documentation.
      # @return [String]
      def resolve_infer_name(pname, infer_name)
        infer_name ? infer_name.call(pname) : pname
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_kwarg_line (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the keyword argument
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting
      # @return [String]
      def build_kwarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = arg_node.children.first.to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, "#{pname}:",
                               infer_default: nil,
                               fallback_type: opts[:fallback_type],
                               treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_kwoptarg_line (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the optional keyword argument
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting
      # @return [String]
      def build_kwoptarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname, default = *arg_node
        pname = pname.to_s
        default_loc = default&.loc
        default_src = default_loc&.expression&.source
        ty = lookup_param_type(external_sig, param_types_override, pname, "#{pname}:",
                               infer_default: default_src,
                               fallback_type: opts[:fallback_type],
                               treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_restarg_line (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the rest argument (*args)
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting
      # @return [String]
      def build_restarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = (arg_node.children.first || 'args').to_s
        ty = if external_sig&.rest_positional&.element_type
               "Array<#{external_sig.rest_positional.element_type}>"
             else
               lookup_param_type_by_infer(param_types_override, pname, "*#{pname}",
                                          opts[:fallback_type], opts[:treat_options_keyword_as_hash])
             end
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_kwrestarg_line (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the keyword rest argument (**kwargs)
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting
      # @return [String]
      def build_kwrestarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = (arg_node.children.first || 'kwargs').to_s
        ty = external_sig&.rest_keywords&.type ||
             lookup_param_type_by_infer(param_types_override, pname, "**#{pname}",
                                        opts[:fallback_type], opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_blockarg_line (instance visibility: private)
      # @param [Parser::AST::Node] arg_node AST node for the block argument (&block)
      # @param [String] indent indentation string for doc comment lines
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [Object] opts additional options for param formatting
      # @return [String]
      def build_blockarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = (arg_node.children.first || 'block').to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, "&#{pname}",
                               infer_default: nil,
                               fallback_type: opts[:fallback_type],
                               treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #lookup_param_type (instance visibility: private)
      # @param [Object, nil] external_sig external method signature for type overrides
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [String] pname the parameter name string
      # @param [String] infer_name parameter name string or transformed version for inference
      # @param [Object] opts additional options including infer_default, fallback_type, treat_options_keyword_as_hash
      # @return [String]
      def lookup_param_type(external_sig, param_types_override, pname, infer_name, **opts)
        external_sig&.param_types&.[](pname) ||
          override_param_type_for(pname, param_types_override) ||
          Infer.infer_param_type(infer_name, opts[:infer_default],
                                 fallback_type: opts[:fallback_type],
                                 treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #lookup_param_type_by_infer (instance visibility: private)
      # @param [Hash<String, String>, nil] param_types_override map of parameter name to override type
      # @param [String] pname the parameter name string
      # @param [String] infer_name parameter name string or transformed version for inference
      # @param [String] fallback_type default type string when inference fails
      # @param [Boolean, nil] treat_options_keyword_as_hash whether to treat options keyword as Hash type
      # @return [String]
      def lookup_param_type_by_infer(param_types_override, pname, infer_name, fallback_type,
                                     treat_options_keyword_as_hash)
        override_param_type_for(pname, param_types_override) ||
          Infer.infer_param_type(infer_name, nil,
                                 fallback_type: fallback_type,
                                 treat_options_keyword_as_hash: treat_options_keyword_as_hash || false)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #format_param_tag (instance visibility: private)
      # @param [String] indent indentation string for the doc line
      # @param [String] name the parameter name
      # @param [String] type the parameter type string
      # @param [String] documentation optional documentation text appended to the tag
      # @param [Symbol, String] style param tag style (:type_name or :name_type)
      # @return [String]
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #append_option_lines (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Object] default Param documentation.
      # @param [String] indent Param documentation.
      # @param [String] pname Param documentation.
      # @param [String] fallback_type Param documentation.
      # @return [void]
      def append_option_lines(lines, default, indent, pname, fallback_type)
        hash_option_pairs(default).each do |pair|
          lines << build_option_line(pair, indent, pname, fallback_type)
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #hash_option_pairs (instance visibility: private)
      # @param [Object] node AST node for the default value, expected to be :hash type
      # @return [Array<Parser::AST::Node>]
      def hash_option_pairs(node)
        return [] unless node&.type == :hash

        node.children.select { |child| child.is_a?(Parser::AST::Node) && child.type == :pair }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_option_line (instance visibility: private)
      # @param [Object] pair AST pair node containing key and value
      # @param [String] indent indentation string for the doc line
      # @param [String] pname the parent parameter name for @option scope
      # @param [String] fallback_type default type string when inference fails
      # @return [String]
      def build_option_line(pair, indent, pname, fallback_type)
        key_node, value_node = pair.children
        option_key = option_key_name(key_node)
        option_type = Infer::Literals.type_from_literal(value_node, fallback_type: fallback_type)
        option_default = node_default_literal(value_node)

        line = "#{indent}# @option #{pname} [#{option_type}] :#{option_key}"
        line += " (#{option_default})" if option_default
        line += ' Description of this option.'
        line
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #option_key_name (instance visibility: private)
      # @param [Object] key_node AST node for the hash key (:sym or :str type)
      # @return [String]
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
      # @param [Object] node AST node whose source text to extract
      # @return [String, nil]
      def node_default_literal(node)
        expression = node&.loc&.expression
        expression&.source
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #override_param_type_for (instance visibility: private)
      # @param [String] pname the parameter name to look up
      # @param [Hash<Object, Object>, nil] override_map hash map of parameter name to override type
      # @return [String, nil]
      def override_param_type_for(pname, override_map)
        return nil unless override_map

        key = pname.to_s
        override_map[key] || override_map[:"#{key}"] || override_map["#{key}:"] || override_map[:"#{key}:"]
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_param_description (instance visibility: private)
      # @param [String] line Param documentation.
      # @return [String, nil]
      def extract_param_description(line)
        m = line.match(/@param\s+\[[^\]]+\]\s+\S+\s+(.+)/) || line.match(/@param\s+\S+\s+\[[^\]]+\]\s+(.+)/)
        desc = m[1]&.strip if m
        desc unless desc&.empty?
      end

      ARG_DEFAULT_NAMES = { restarg: 'args', kwrestarg: 'kwargs', blockarg: 'block' }.freeze

      # Method documentation.
      #
      # @note module_function: when included, also defines #param_name_from_arg (instance visibility: private)
      # @param [Parser::AST::Node] arg_node Param documentation.
      # @return [String, nil]
      def param_name_from_arg(arg_node)
        return nil if arg_node.type == :forward_arg

        (arg_node.children.first || ARG_DEFAULT_NAMES[arg_node.type] || '').to_s
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines
      #   #extract_param_name_from_param_line (instance visibility: private)
      # @param [String] line a `@param` doc line
      # @return [String, nil] the parameter name or nil
      def extract_param_name_from_param_line(line)
        return Regexp.last_match(1) if line =~ /@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines
      #   #extract_param_type_from_param_line (instance visibility: private)
      # @param [String] line a `@param` tag line
      # @return [String, nil]
      def extract_param_type_from_param_line(line)
        if (m = line.match(/@param\s+\[([^\]]+)\]\s+\S+/) || line.match(/@param\s+\S+\s+\[([^\]]+)\]/))
          m[1]
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_missing_raises! (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Object] ctx Param documentation.
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_missing_return! (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [void]
      def collect_missing_return!(lines, reasons, **ctx)
        return unless ctx[:config].emit_return_tag?(ctx[:scope], ctx[:visibility])

        if !ctx[:info][:has_return]
          record_missing_return(lines, reasons, ctx)
        elsif return_type_changed?(ctx)
          record_updated_return(lines, reasons, ctx)
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #record_missing_return (instance visibility: private)
      # @param [Array<String>] lines array of output doc lines being accumulated
      # @param [Array<Hash<Symbol, Object>>] reasons array of reason hashes for --explain output
      # @param [Hash<Symbol, Object>] ctx merged context hash with normal_type and indent
      # @return [void]
      def record_missing_return(lines, reasons, ctx)
        lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n"
        reasons << { type: :missing_return, message: 'missing @return' }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #record_updated_return (instance visibility: private)
      # @param [Array<String>] lines array of output doc lines being accumulated
      # @param [Array<Hash<Symbol, Object>>] reasons array of reason hashes for --explain output
      # @param [Hash<Symbol, Object>] ctx merged context hash with normal_type and info
      # @return [void]
      def record_updated_return(lines, reasons, ctx)
        lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n" unless ctx[:strategy] == :safe
        reasons << { type: :updated_return,
                     message: "updated @return from #{ctx[:info][:return_type]} to #{ctx[:normal_type]}" }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #return_type_changed? (instance visibility: private)
      # @param [Hash<Symbol, Object>] ctx merged context hash with external_sig, info, and normal_type
      # @return [Boolean]
      def return_type_changed?(ctx)
        ctx[:external_sig] && ctx[:info][:return_type] && ctx[:info][:return_type] != ctx[:normal_type]
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines
      #   #collect_missing_rescue_returns! (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Object] ctx Param documentation.
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_missing_plugin_tags! (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Array<Hash<Symbol, Object>>] reasons Param documentation.
      # @param [Object] ctx Param documentation.
      # @return [void]
      def collect_missing_plugin_tags!(lines, reasons, **ctx)
        plugin_tags = Docscribe::Plugin.run_tag_plugins(build_plugin_context(ctx[:insertion],
                                                                             normal_type: ctx[:normal_type]))
        plugin_tags.concat(Array(ctx[:override_tags])) if ctx[:override_tags]

        plugin_tags.each { |tag| record_plugin_tag(tag, lines, reasons, ctx) }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #record_plugin_tag (instance visibility: private)
      # @param [Object] tag plugin tag object to render and record
      # @param [Array<String>] lines array of output doc lines being accumulated
      # @param [Array<Hash<Symbol, Object>>] reasons array of reason hashes for --explain output
      # @param [Hash<Symbol, Object>] ctx merged context hash with info and indent
      # @return [void]
      def record_plugin_tag(tag, lines, reasons, ctx)
        return if ctx[:info][:plugin_tags]&.[](tag.name)

        rendered = render_plugin_tags([tag], ctx[:indent]).first
        lines << "#{rendered}\n"
        reasons << { type: :missing_plugin_tag, message: "missing @#{tag.name}" }
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #debug_warn (instance visibility: private)
      # @param [StandardError] error the error that occurred
      # @param [Object] insertion the method insertion being processed
      # @param [String] name the method name
      # @param [String] phase the processing phase
      # @return [void]
      def debug_warn(error, insertion:, name:, phase:)
        return unless debug?

        where = build_debug_location(insertion, name)
        warn "Docscribe DEBUG: #{phase} failed at #{where}: #{error.class}: #{error.message}"
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_debug_location (instance visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [String] name the method name string
      # @return [String]
      def build_debug_location(insertion, name)
        return name.to_s unless insertion

        expr = insertion.node.loc.expression
        buf = expr.source_buffer.name
        sym = insertion.scope == :class ? '.' : '#'
        ctr = insertion.container || 'Object'
        +"#{buf}:#{expr.line} #{ctr}#{sym}#{name}"
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #debug? (instance visibility: private)
      # @return [Boolean]
      def debug?
        ENV['DOCSCRIBE_DEBUG'] == '1'
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_plugin_context (instance visibility: private)
      # @param [Object] insertion Param documentation.
      # @param [String] normal_type resolved return type
      # @return [Object]
      def build_plugin_context(insertion, normal_type:)
        node = insertion.node
        source = safe_node_source(node)
        new_plugin_context(insertion, node, source, normal_type)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #new_plugin_context (instance visibility: private)
      # @param [Object] insertion Param documentation.
      # @param [Parser::AST::Node] node Param documentation.
      # @param [String] source Param documentation.
      # @param [String] normal_type Param documentation.
      # @return [Object]
      def new_plugin_context(insertion, node, source, normal_type)
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #safe_node_source (instance visibility: private)
      # @raise [StandardError]
      # @param [Parser::AST::Node] node Param documentation.
      # @return [String]
      # @return [String] if StandardError
      def safe_node_source(node)
        node.loc.expression.source
      rescue StandardError
        ''
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #render_plugin_tags (instance visibility: private)
      # @param [Array<Object>] tags Param documentation.
      # @param [String] indent Param documentation.
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
