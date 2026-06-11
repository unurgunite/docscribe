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
        forward_arg: ->(*) { [] }
      }.freeze

      # Build a complete doc block for one collected method insertion.
      #
      # External signatures, when available, override inferred param and return
      # types.
      #
      # @note module_function: when included, also defines #build (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [Docscribe::Config] config
      # @param [Hash] opts additional keyword options forwarded to doc_setup
      # @raise [StandardError]
      # @return [String, nil]
      def build(insertion, config:, **opts)
        setup = doc_setup(insertion, config: config, **opts)
        return nil unless setup

        build_unsafe(insertion, config: config, setup: setup, **opts)
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: '(unknown)', phase: 'DocBuilder.build')
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
      # @param [Hash] options additional keyword options forwarded to downstream methods
      # @raise [StandardError]
      # @return [String, nil]
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
      # @param [Hash] options additional keyword options forwarded to downstream methods
      # @raise [StandardError]
      # @return [Hash]
      def build_missing_merge_result(insertion, existing_lines:, config:, **options)
        setup = doc_setup(insertion, config: config, **options)
        return { lines: [], reasons: [] } unless setup

        info = parse_existing_doc_tags(existing_lines)
        collect_all_missing(setup, info, insertion, config, options)
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: setup[:name] || '(unknown)',
                      phase: 'DocBuilder.build_missing_merge_result')
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
        resolve_doc_setup!(setup, node, name, config, opts)
      end

      # Build without rescue wrapping (extracted for metric reduction).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [Docscribe::Config] config
      # @param [Hash] setup
      # @param [Hash] opts
      # @return [String, nil]
      def build_unsafe(insertion, config:, setup:, **opts)
        _, pl, rt = build_param_and_raise_info(setup, config, opts)
        lines = build_doc_lines(setup, config: config, insertion: insertion, params_lines: pl, raise_types: rt,
                                       override_tags: opts[:override_tags])
        lines.map { |l| "#{l}\n" }.join
      end

      # Build param types, param lines, and raise types for doc block.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @param [Hash] setup
      # @param [Docscribe::Config] config
      # @param [Hash] opts
      # @return [Array]
      def build_param_and_raise_info(setup, config, opts)
        pt = opts[:param_types] || build_param_types_from_node(setup[:node], external_sig: setup[:external_sig],
                                                                             config: config)
        pl = if config.emit_param_tags?
               build_params_lines(setup[:node], setup[:indent], external_sig: setup[:external_sig], config: config,
                                                                param_types_override: pt)
             end
        rt = config.emit_raise_tags? ? Docscribe::Infer.infer_raises_from_node(setup[:node]) : []
        [pt, pl, rt]
      end

      # Resolve external signature, returns spec, and normal type for doc setup.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @param [Hash] setup
      # @param [Parser::AST::Node] node
      # @param [String] name
      # @param [Docscribe::Config] config
      # @param [Hash] opts
      # @return [Hash]
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
        init = init_parse_info
        Array(lines).each_with_object(init) do |line, info|
          extract_param_info(line, info[:param_names], info[:param_types])
          extract_return_info(line, info)
          extract_visibility_info(line, info)
          extract_raise_info(line, info[:raise_types])
          extract_plugin_info(line, info[:plugin_tags])
        end
      end

      # Initialize an empty parse info hash.
      #
      # @note module_function: when included, also defines #init_parse_info (instance visibility: private)
      # @return [Hash]
      def init_parse_info
        {
          param_names: {}, param_types: {}, raise_types: {}, plugin_tags: {},
          has_return: false, return_type: nil,
          has_private: false, has_protected: false, has_module_function_note: false
        }
      end

      # Build merged destination lines for safe merge mode.
      # Wrapper that delegates to merge_lines_with_context.
      #
      # @note module_function: when included, also defines #merge_dest_lines (instance visibility: private)
      # @param [Object] existing_lines existing doc comment lines to merge into
      # @param [Hash] ctx merge context hash (setup, insertion, config, info, param_types)
      # @return [Object]
      def merge_dest_lines(existing_lines, **ctx)
        merge_lines_with_context(existing_lines, **ctx)
      end

      # Merge dest lines using a context hash (extracted for metric reduction).
      #
      # @note module_function: when included, also defines #merge_lines_with_context (instance visibility: private)
      # @param [Object] existing_lines existing doc comment lines being merged
      # @param [Hash] ctx merge context (setup, insertion, config, info, param_types)
      # @return [Object]
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

      # Build initial line array for merge dest lines.
      #
      # @note module_function: when included, also defines #build_initial_line_ary (instance visibility: private)
      # @param [Array<String>] existing_lines
      # @param [String] indent
      # @return [Array<String>]
      def build_initial_line_ary(existing_lines, indent)
        existing_lines.any? && existing_lines.last.strip != '#' ? ["#{indent}#"] : []
      end

      # Merge all tag lines into a line array.
      #
      # @note module_function: when included, also defines #merge_all_tag_lines (instance visibility: private)
      # @param [Array<String>] base_ary
      # @param [Hash] ctx context hash with setup, config, info, insertion, param_types
      # @return [Array<String>]
      def merge_all_tag_lines(base_ary, **ctx)
        line_ary = base_ary.dup
        merge_tag_lines_core(line_ary, ctx)
        line_ary.concat(merge_rescue_return_lines(ctx[:i], ctx[:s][:rescue_specs], ctx[:config], ctx[:info]))
        line_ary
      end

      # Core tag line merging.
      #
      # @note module_function: when included, also defines #merge_tag_lines_core (instance visibility: private)
      # @param [Array<String>] line_ary
      # @param [Hash] ctx
      # @return [void]
      def merge_tag_lines_core(line_ary, ctx)
        append_merge_tag_lines(line_ary, ctx)
        merge_return_line(line_ary, ctx[:i], ctx[:s], ctx[:config], ctx[:info])
      end

      # Append merge tag lines into line_ary.
      #
      # @note module_function: when included, also defines #append_merge_tag_lines (instance visibility: private)
      # @param [Array<String>] line_ary
      # @param [Hash] ctx
      # @return [void]
      def append_merge_tag_lines(line_ary, ctx)
        line_ary.concat(build_all_merge_tags(ctx))
      end

      # Build an array of all merge tag lines.
      #
      # @note module_function: when included, also defines #build_all_merge_tags (instance visibility: private)
      # @param [Hash] ctx
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

      # Merge return tag line into line_ary.
      #
      # @note module_function: when included, also defines #merge_return_line (instance visibility: private)
      # @param [Array<String>] line_ary
      # @param [Object] config
      # @param [Object] info
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with node, name, types, scope
      # @return [void]
      def merge_return_line(line_ary, indent, setup, config, info)
        emit_ret = config.emit_return_tag?(setup[:scope], setup[:visibility])
        ret_line = merge_return_tag_line(indent, setup[:normal_type], config: config, scope: setup[:scope],
                                                                      visibility: setup[:visibility], info: info)

        line_ary << ret_line if emit_ret && ret_line
      end

      # Collect all missing doc elements and return { lines:, reasons: }.
      # Delegates to collect_missing_all with a merged context hash.
      #
      # @note module_function: when included, also defines #collect_all_missing (instance visibility: private)
      # @param [Object] setup resolved setup hash with node, name, indent, types
      # @param [Object] info parsed existing doc tag information
      # @param [Object] insertion the collected method insertion object
      # @param [Object] config Docscribe configuration object
      # @param [Object] options additional options hash forwarded to missing collector
      # @return [Hash]
      def collect_all_missing(setup, info, insertion, config, options)
        s = setup
        ctx = { node: s[:node], indent: s[:indent], config: config, external_sig: s[:external_sig],
                info: info, strategy: options[:strategy], scope: s[:scope], visibility: s[:visibility],
                normal_type: s[:normal_type], rescue_specs: s[:rescue_specs], insertion: insertion,
                param_types: options[:param_types], override_tags: options[:override_tags] }
        collect_missing_all(ctx)
      end

      # Collect all missing elements via context hash.
      #
      # @note module_function: when included, also defines #collect_missing_all (instance visibility: private)
      # @param [Hash] ctx
      # @return [Hash]
      def collect_missing_all(ctx)
        lines = []
        reasons = []
        collect_missing_visibility!(lines, reasons, **ctx)
        collect_missing_module_function_note!(lines, reasons, **ctx)
        collect_missing_params!(lines, reasons, **ctx)
        collect_missing_raises!(lines, reasons, **ctx)
        collect_missing_return!(lines, reasons, **ctx)
        collect_missing_rescue_returns!(lines, reasons, **ctx)
        collect_missing_plugin_tags!(lines, reasons, **ctx)
        { lines: lines, reasons: reasons }
      end

      # Extract param info from a doc line.
      # Parses @param lines and populates param_names and param_types hashes.
      #
      # @note module_function: when included, also defines #extract_param_info (instance visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] param_names hash tracking existing @param names
      # @param [Object] param_types hash tracking existing @param types
      # @return [Object]
      def extract_param_info(line, param_names, param_types)
        return unless (pname = extract_param_name_from_param_line(line))

        param_names[pname] = true
        unless (type_match = line.match(/@param\s+\[([^\]]+)\]\s+\S+/) || line.match(/@param\s+\S+\s+\[([^\]]+)\]/))
          return
        end

        param_types[pname] = type_match[1]
      end

      # Extract return info from a doc line.
      # Detects @return tags and records type and presence in info hash.
      #
      # @note module_function: when included, also defines #extract_return_info (instance visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] info parse info hash to update with return data
      # @return [Object]
      def extract_return_info(line, info)
        return unless line.match?(/^\s*#\s*@return\b/)

        info[:has_return] = true
        return unless (m = line.match(/@return\s+\[([^\]]+)\]/))

        info[:return_type] = m[1]
      end

      # Extract visibility info from a doc line.
      # Detects @private, @protected, and @note module_function tags.
      #
      # @note module_function: when included, also defines #extract_visibility_info (instance visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] info parse info hash to update with visibility flags
      # @return [Object]
      def extract_visibility_info(line, info)
        info[:has_private] ||= line.match?(/^\s*#\s*@private\b/)
        info[:has_protected] ||= line.match?(/^\s*#\s*@protected\b/)
        info[:has_module_function_note] ||= line.match?(/^\s*#\s*@note\s+module_function:/)
      end

      # Extract raise info from a doc line.
      # Parses @raise tags and records exception types in raise_types hash.
      #
      # @note module_function: when included, also defines #extract_raise_info (instance visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] raise_types hash tracking existing @raise types
      # @return [Object]
      def extract_raise_info(line, raise_types)
        extract_raise_types_from_line(line).each { |t| raise_types[t] = true }
      end

      # Extract plugin tag info from a doc line.
      # Captures any @tag_name from the line into the plugin_tags hash.
      #
      # @note module_function: when included, also defines #extract_plugin_info (instance visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] plugin_tags hash tracking existing plugin tag names
      # @return [Object]
      def extract_plugin_info(line, plugin_tags)
        return unless (m = line.match(/^\s*#\s*@(\w+)\b/))

        plugin_tags[m[1]] = true
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
      # @param [Object] str comma-separated exception names string from @raise brackets
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
        return unless node

        args = extract_args_from_node(node)
        return unless args

        param_types = {}
        collect_all_param_types(args, param_types, external_sig, config)
        param_types.empty? ? nil : param_types
      end

      # Collect param types for all args using dispatch hash.
      #
      # @note module_function: when included, also defines #collect_all_param_types (instance visibility: private)
      # @param [Object] args
      # @param [Hash] param_types
      # @param [Object] external_sig
      # @param [Object] config
      # @return [void]
      def collect_all_param_types(args, param_types, external_sig, config)
        (args.children || []).each do |a|
          collector = PARAM_TYPE_COLLECTORS[a.type]
          collector&.call(a, param_types, external_sig, config)
        end
      end

      # Collect param type for a required/keyword argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] param_types hash accumulating parameter name-to-type mappings
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] config Docscribe configuration for fallback type options
      # @param [Object] infer_name lambda to transform parameter name for inference
      # @param [Object] arg_node AST node for the required/keyword argument
      # @return [Object]
      def collect_param_type(arg_node, param_types, external_sig, config, infer_name:)
        pname = arg_node.children.first.to_s
        infer_pname = resolve_infer_name(pname, infer_name)
        ty = external_sig&.param_types&.[](pname) ||
             Infer.infer_param_type(infer_pname, nil,
                                    fallback_type: config.fallback_type,
                                    treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?)
        param_types[pname] = ty
      end

      # Collect param type for an optional/keyword optional argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] param_types hash accumulating parameter name-to-type mappings
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] config Docscribe configuration for fallback type options
      # @param [Object] infer_name lambda to transform parameter name for inference
      # @param [Object] arg_node AST node for the optional/keyword optional argument
      # @return [Object]
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
      # @note also defines #merge_module_function_note_lines (instance: private)
      # @note module_function: when included, also defines # (instance visibility: private)
      # @param [String] indent
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [String] name
      # @param [Hash] info
      # @return [Array<String>]
      def merge_module_function_note_lines(indent, insertion, name, info)
        unless insertion.respond_to?(:module_function) && insertion.module_function && !info[:has_module_function_note]
          return []
        end

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
      # @param [Hash] opts additional options including external_sig, param_types, info
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
      # @param [Hash] opts additional options including scope, visibility, info
      # @return [String, nil]
      def merge_return_tag_line(indent, normal_type, config:, **opts)
        return unless config.emit_return_tag?(opts[:scope], opts[:visibility])
        return if opts[:info][:has_return]

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

        add_missing_private(lines, reasons, ctx)
        add_missing_protected(lines, reasons, ctx)
      end

      # Add @private tag if missing.
      #
      # @note module_function: when included, also defines #add_missing_private (instance visibility: private)
      # @param [Array] lines
      # @param [Array] reasons
      # @param [Hash] ctx
      # @return [void]
      def add_missing_private(lines, reasons, ctx)
        return unless ctx[:visibility] == :private && !ctx[:info][:has_private]

        lines << "#{ctx[:indent]}# @private\n"
        reasons << { type: :missing_visibility, message: 'missing @private' }
      end

      # Add @protected tag if missing.
      #
      # @note module_function: when included, also defines #add_missing_protected (instance visibility: private)
      # @param [Array] lines
      # @param [Array] reasons
      # @param [Hash] ctx
      # @return [void]
      def add_missing_protected(lines, reasons, ctx)
        return unless ctx[:visibility] == :protected && !ctx[:info][:has_protected]

        lines << "#{ctx[:indent]}# @protected\n"
        reasons << { type: :missing_visibility, message: 'missing @protected' }
      end

      # Collect missing module_function note for build_missing_merge_result.
      #
      # @note also defines #collect_missing_module_function_note! (instance: private)
      # @note module_function: when included, also defines # (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
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

      # Collect missing/updated param lines for build_missing_merge_result.
      #
      # @note module_function: when included, also defines #collect_missing_params! (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Array<Hash>] reasons
      # @param [Hash] ctx
      # @return [void]
      def collect_missing_params!(lines, reasons, **ctx)
        return unless ctx[:config].emit_param_tags?

        all_params = build_params_lines(ctx[:node], ctx[:indent],
                                        external_sig: ctx[:external_sig], config: ctx[:config],
                                        param_types_override: ctx[:param_types])
        return unless all_params

        all_params.each { |pl| collect_param_from_line(pl, lines, reasons, ctx) }
      end

      # Collect a single param line for build_missing_merge_result.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with build parameters
      # @param [Object] param_line a single @param tag line to evaluate
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
      # @param [Object] pname the parameter name string
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with build parameters
      # @param [Object] param_line a single @param tag line to evaluate
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
        args = extract_args_from_node(node)
        return nil unless args

        build_all_param_lines(args, indent, external_sig, param_types_override, config)
      end

      # Build all param lines for args.
      #
      # @note module_function: when included, also defines #build_all_param_lines (instance visibility: private)
      # @param [Object] args
      # @param [String] indent
      # @param [Object] external_sig
      # @param [Object] param_types_override
      # @param [Docscribe::Config] config
      # @return [Array<String>, nil]
      def build_all_param_lines(args, indent, external_sig, param_types_override, config)
        fb = config.fallback_type
        tk = config.treat_options_keyword_as_hash?
        ts = config.param_tag_style
        pd = config.include_param_documentation? ? config.param_documentation : ''
        params = (args.children || []).each_with_object([]) do |a, p|
          p.concat(build_param_line(a, indent, external_sig, param_types_override,
                                    fallback_type: fb, treat_options_keyword_as_hash: tk,
                                    param_documentation: pd, param_tag_style: ts))
        end
        params.empty? ? nil : params
      end

      # Build doc lines for a full doc block.
      # Delegates to assemble_doc_lines with setup and context.
      #
      # @note module_function: when included, also defines #build_doc_lines (instance visibility: private)
      # @param [Object] setup method setup hash with indent, name, types, scope
      # @param [Object] config Docscribe configuration object
      # @param [Hash] kwargs additional keyword args including insertion, params_lines, raise_types, override_tags
      # @return [Object]
      def build_doc_lines(setup, config:, **kwargs)
        i = setup[:indent]
        assemble_doc_lines(i, setup, config: config, insertion: kwargs[:insertion],
                                     params_lines: kwargs[:params_lines],
                                     raise_types: kwargs[:raise_types], override_tags: kwargs[:override_tags])
      end

      # Assemble all doc lines into a single array.
      #
      # @note module_function: when included, also defines #assemble_doc_lines (instance visibility: private)
      # @param [String] indent indent
      # @param [Hash] setup setup
      # @param [Hash] ctx context hash with config, insertion, params_lines, raise_types, override_tags
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

      # Append body lines to a doc line array.
      #
      # @note module_function: when included, also defines #append_assemble_body_lines (instance visibility: private)
      # @param [Array<String>] line_ary
      # @param [Hash] ctx
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, types, scope
      # @return [void]
      def append_assemble_body_lines(line_ary, indent, setup, ctx)
        line_ary.concat(build_all_body_tags(indent, setup, ctx))
      end

      # Build all body tag lines for a doc block.
      #
      # @note module_function: when included, also defines #build_all_body_tags (instance visibility: private)
      # @param [Hash] ctx
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, types, scope
      # @return [Array<String>]
      def build_all_body_tags(indent, setup, ctx)
        result = core_body_tags(indent, setup, ctx)
        result.insert(3, ctx[:params_lines]) if ctx[:params_lines]
        result.flatten
      end

      # Core body tags without optional params_lines.
      #
      # @note module_function: when included, also defines #core_body_tags (instance visibility: private)
      # @param [Hash] ctx
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, types, scope
      # @return [Array]
      def core_body_tags(indent, setup, ctx)
        config = ctx[:config]
        [
          defaults_and_visibility(indent, config, setup[:scope], setup[:visibility]),
          build_module_function_note_lines(indent, ctx[:insertion], setup[:name]),
          build_raise_tag_lines(indent, ctx[:raise_types], config),
          build_return_line_if_needed(indent, setup, config),
          build_rescue_return_lines(indent, setup[:rescue_specs], config),
          build_plugin_tag_lines(ctx[:insertion], indent, setup[:normal_type], ctx[:override_tags])
        ]
      end

      # Build default msg and visibility tags.
      #
      # @note module_function: when included, also defines #defaults_and_visibility (instance visibility: private)
      # @param [Object] config
      # @param [Symbol] scope
      # @param [Symbol] visibility
      # @param [Object] indent indentation string for doc comment lines
      # @return [Array<String>]
      def defaults_and_visibility(indent, config, scope, visibility)
        [
          build_default_msg_lines(indent, config, scope, visibility),
          build_visibility_tag_lines(indent, visibility, config)
        ].flatten
      end

      # Build return tag line if emit condition is met.
      #
      # @note module_function: when included, also defines #build_return_line_if_needed (instance visibility: private)
      # @param [Docscribe::Config] config
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, normal_type, scope, visibility
      # @return [Array<String>]
      def build_return_line_if_needed(indent, setup, config)
        emit_ret = config.emit_return_tag?(setup[:scope], setup[:visibility])
        ret_line = build_return_tag_line(indent, setup[:normal_type], config, setup[:scope], setup[:visibility])
        emit_ret && ret_line ? [ret_line] : []
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

      # Build a param line for a single argument node.
      # Dispatches to the appropriate builder via PARAM_BUILDERS by arg type.
      #
      # @note module_function: when included, also defines #build_param_line (instance visibility: private)
      # @param [Object] arg_node AST node for the argument
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Hash] opts additional options for param formatting (fallback_type, param_tag_style, etc.)
      # @return [Object]
      def build_param_line(arg_node, indent, external_sig, param_types_override, **opts)
        PARAM_BUILDERS.fetch(arg_node.type, lambda { |*|
          []
        }).call(arg_node, indent, external_sig, param_types_override, **opts)
      end

      # Build header line(s) for a doc block.
      #
      # @note module_function: when included, also defines #build_header_lines (instance visibility: private)
      # @param [String] indent
      # @param [Docscribe::Config] config
      # @param [Hash] opts additional options including container, method_symbol, name, normal_type
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
      # @note also defines #build_module_function_note_lines (instance: private)
      # @note module_function: when included, also defines # (instance visibility: private)
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
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] arg_node AST node for the required argument
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
      def build_arg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = arg_node.children.first.to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, pname,
                               infer_default: nil,
                               fallback_type: opts[:fallback_type],
                               treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Build param lines for an optional argument (including @option lines).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] arg_node AST node for the optional argument
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
      def build_optarg_lines(arg_node, indent, external_sig, param_types_override, **opts)
        pname, default = *arg_node
        pname = pname.to_s
        ty = optarg_type(pname, default, external_sig, param_types_override, opts)
        lines = [format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])]

        append_option_lines(lines, default, indent, pname, opts[:fallback_type])
        lines
      end

      # Resolve optarg type.
      #
      # @note module_function: when included, also defines #optarg_type (instance visibility: private)
      # @param [String] pname
      # @param [Object] default
      # @param [Object] external_sig
      # @param [Object] param_types_override
      # @param [Hash] opts
      # @return [String]
      def optarg_type(pname, default, external_sig, param_types_override, opts)
        default_src = source_from_node(default)
        lookup_param_type(external_sig, param_types_override, pname, pname,
                          infer_default: default_src,
                          fallback_type: opts[:fallback_type],
                          treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
      end

      # Extract source text from an AST node.
      #
      # @note module_function: when included, also defines #source_from_node (instance visibility: private)
      # @param [Object] node
      # @return [String, nil]
      def source_from_node(node)
        loc = node&.loc
        loc&.expression&.source
      end

      # Resolve the infer name string from a param name and infer_name lambda.
      #
      # @note module_function: when included, also defines #resolve_infer_name (instance visibility: private)
      # @param [String] pname
      # @param [Proc, nil] infer_name
      # @return [String]
      def resolve_infer_name(pname, infer_name)
        infer_name ? infer_name.call(pname) : pname
      end

      # Build a param line for a keyword argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] arg_node AST node for the keyword argument
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
      def build_kwarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = arg_node.children.first.to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, "#{pname}:",
                               infer_default: nil,
                               fallback_type: opts[:fallback_type],
                               treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Build a param line for an optional keyword argument.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] arg_node AST node for the optional keyword argument
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
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

      # Build a param line for a rest argument (*args).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] arg_node AST node for the rest argument (*args)
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
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

      # Build a param line for a keyword rest argument (**kwargs).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] arg_node AST node for the keyword rest argument (**kwargs)
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
      def build_kwrestarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = (arg_node.children.first || 'kwargs').to_s
        ty = external_sig&.rest_keywords&.type ||
             lookup_param_type_by_infer(param_types_override, pname, "**#{pname}",
                                        opts[:fallback_type], opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Build a param line for a block argument (&block).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] arg_node AST node for the block argument (&block)
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
      def build_blockarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = (arg_node.children.first || 'block').to_s
        ty = lookup_param_type(external_sig, param_types_override, pname, "&#{pname}",
                               infer_default: nil,
                               fallback_type: opts[:fallback_type],
                               treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Three-tier type lookup: external_sig -> override -> inference.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] pname the parameter name string
      # @param [Object] infer_name parameter name string or transformed version for inference
      # @param [Hash] opts additional options including infer_default, fallback_type, treat_options_keyword_as_hash
      # @return [Object]
      def lookup_param_type(external_sig, param_types_override, pname, infer_name, **opts)
        external_sig&.param_types&.[](pname) ||
          override_param_type_for(pname, param_types_override) ||
          Infer.infer_param_type(infer_name, opts[:infer_default],
                                 fallback_type: opts[:fallback_type],
                                 treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
      end

      # Two-tier type lookup: override -> inference (for rest/kwrest types).
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] pname the parameter name string
      # @param [Object] infer_name parameter name string or transformed version for inference
      # @param [Object] fallback_type default type string when inference fails
      # @param [Object] treat_options_keyword_as_hash whether to treat options keyword as Hash type
      # @return [Object]
      def lookup_param_type_by_infer(param_types_override, pname, infer_name, fallback_type,
                                     treat_options_keyword_as_hash)
        override_param_type_for(pname, param_types_override) ||
          Infer.infer_param_type(infer_name, nil,
                                 fallback_type: fallback_type,
                                 treat_options_keyword_as_hash: treat_options_keyword_as_hash)
      end

      # Format a YARD @param tag line with optional documentation text.
      #
      # @note module_function: when included, also defines #format_param_tag (instance visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] name the parameter name
      # @param [Object] type the parameter type string
      # @param [Object] documentation optional documentation text appended to the tag
      # @param [Object] style param tag style (:type_name or :name_type)
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

      # Append @option lines for hash defaults.
      #
      # @note module_function: when included, also defines #append_option_lines (instance visibility: private)
      # @param [Array] lines
      # @param [Object] default
      # @param [String] indent
      # @param [String] pname
      # @param [Object] fallback_type
      # @return [void]
      def append_option_lines(lines, default, indent, pname, fallback_type)
        hash_option_pairs(default).each do |pair|
          lines << build_option_line(pair, indent, pname, fallback_type)
        end
      end

      # Extract hash option pairs from a default value node.
      #
      # @note module_function: when included, also defines #hash_option_pairs (instance visibility: private)
      # @param [Object] node AST node for the default value, expected to be :hash type
      # @return [Object]
      def hash_option_pairs(node)
        return [] unless node&.type == :hash

        node.children.select { |child| child.is_a?(Parser::AST::Node) && child.type == :pair }
      end

      # Build an @option line from a hash pair node.
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Object] pair AST pair node containing key and value
      # @param [Object] indent indentation string for the doc line
      # @param [Object] pname the parent parameter name for @option scope
      # @param [Object] fallback_type default type string when inference fails
      # @return [Object]
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

      # Extract the option key name from a hash key node.
      #
      # @note module_function: when included, also defines #option_key_name (instance visibility: private)
      # @param [Object] key_node AST node for the hash key (:sym or :str type)
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

      # Extract the source text of a default value node.
      #
      # @note module_function: when included, also defines #node_default_literal (instance visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @return [Object]
      def node_default_literal(node)
        expression = node&.loc&.expression
        expression&.source
      end

      # Look up a parameter type from an override map.
      #
      # @note module_function: when included, also defines #override_param_type_for (instance visibility: private)
      # @param [Object] pname the parameter name to look up
      # @param [Object] override_map hash map of parameter name to override type
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
      # @note also defines #extract_param_name_from_param_line (instance: private)
      # @note module_function: when included, also defines # (instance visibility: private)
      # @param [String] line a `@param` doc line
      # @return [String, nil] the parameter name or nil
      def extract_param_name_from_param_line(line)
        return Regexp.last_match(1) if line =~ /@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Extract the type from a `@param` tag line.
      #
      # @note also defines #extract_param_type_from_param_line (instance: private)
      # @note module_function: when included, also defines # (instance visibility: private)
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
          record_missing_return(lines, reasons, ctx)
        elsif return_type_changed?(ctx)
          record_updated_return(lines, reasons, ctx)
        end
      end

      # Record a missing @return tag and its reason.
      #
      # @note module_function: when included, also defines #record_missing_return (instance visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with normal_type and indent
      # @return [Object]
      def record_missing_return(lines, reasons, ctx)
        lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n"
        reasons << { type: :missing_return, message: 'missing @return' }
      end

      # Record an updated @return tag and its reason.
      #
      # @note module_function: when included, also defines #record_updated_return (instance visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with normal_type and info
      # @return [Object]
      def record_updated_return(lines, reasons, ctx)
        lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n" unless ctx[:strategy] == :safe
        reasons << { type: :updated_return,
                     message: "updated @return from #{ctx[:info][:return_type]} to #{ctx[:normal_type]}" }
      end

      # Check if the return type changed between existing doc and inferred/signature type.
      # Compares existing return type to the resolved normal type.
      #
      # @note module_function: when included, also defines #return_type_changed? (instance visibility: private)
      # @param [Object] ctx merged context hash with external_sig, info, and normal_type
      # @return [Object]
      def return_type_changed?(ctx)
        ctx[:external_sig] && ctx[:info][:return_type] && ctx[:info][:return_type] != ctx[:normal_type]
      end

      # Collect missing rescue conditional returns for build_missing_merge_result.
      #
      # @note also defines #collect_missing_rescue_returns! (instance: private)
      # @note module_function: when included, also defines # (instance visibility: private)
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
        plugin_tags = Docscribe::Plugin.run_tag_plugins(build_plugin_context(ctx[:insertion],
                                                                             normal_type: ctx[:normal_type]))
        plugin_tags.concat(Array(ctx[:override_tags])) if ctx[:override_tags]

        plugin_tags.each { |tag| record_plugin_tag(tag, lines, reasons, ctx) }
      end

      # Record a missing plugin tag and its reason.
      #
      # @note module_function: when included, also defines #record_plugin_tag (instance visibility: private)
      # @param [Object] tag plugin tag object to render and record
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with info and indent
      # @return [Object]
      def record_plugin_tag(tag, lines, reasons, ctx)
        return if ctx[:info][:plugin_tags]&.[](tag.name)

        rendered = render_plugin_tags([tag], ctx[:indent]).first
        lines << "#{rendered}\n"
        reasons << { type: :missing_plugin_tag, message: "missing @#{tag.name}" }
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

        where = build_debug_location(insertion, name)
        warn "Docscribe DEBUG: #{phase} failed at #{where}: #{error.class}: #{error.message}"
      end

      # Build a human-readable location string for debug output.
      # Formats as "file.rb:line Container#method" for error reporting.
      #
      # @note module_function: when included, also defines #build_debug_location (instance visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] name the method name string
      # @return [Object]
      def build_debug_location(insertion, name)
        return name.to_s unless insertion

        expr = insertion.node.loc.expression
        buf = expr.source_buffer.name
        sym = insertion.scope == :class ? '.' : '#'
        ctr = insertion.container || 'Object'
        +"#{buf}:#{expr.line} #{ctr}#{sym}#{name}"
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
        source = safe_node_source(node)
        new_plugin_context(insertion, node, source, normal_type)
      end

      # Build a Plugin::Context from parts.
      #
      # @note module_function: when included, also defines #new_plugin_context (instance visibility: private)
      # @param [Object] insertion
      # @param [Object] node
      # @param [String] source
      # @param [String] normal_type
      # @return [Docscribe::Plugin::Context]
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

      # Safely extract source text from a node.
      #
      # @note module_function: when included, also defines #safe_node_source (instance visibility: private)
      # @param [Parser::AST::Node] node
      # @raise [StandardError]
      # @return [String]
      def safe_node_source(node)
        node.loc.expression.source
      rescue StandardError
        ''
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
