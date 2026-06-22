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

      # Build
      #
      # @note module_function: defines #build (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] config Docscribe configuration object
      # @param [Hash] opts additional keyword options forwarded to doc_setup
      # @raise [StandardError]
      # @return [Object] if StandardError
      # @return [nil] if StandardError
      def build(insertion, config:, **opts)
        setup = doc_setup(insertion, config: config, **opts)
        return nil unless setup

        build_unsafe(insertion, config: config, setup: setup, **opts)
      rescue StandardError => e
        debug_warn(e, insertion: insertion, name: '(unknown)', phase: 'DocBuilder.build')
        nil
      end

      # Build merge additions
      #
      # @note module_function: defines #build_merge_additions (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] existing_lines existing doc comment lines being merged
      # @param [Object] config Docscribe configuration object
      # @param [Hash] options additional keyword options forwarded to downstream methods
      # @raise [StandardError]
      # @return [Object] if StandardError
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

      # Build missing merge result
      #
      # @note module_function: defines #build_missing_merge_result (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] existing_lines existing doc comment lines being merged
      # @param [Object] config Docscribe configuration object
      # @param [Hash] options additional keyword options forwarded to downstream methods
      # @raise [StandardError]
      # @return [Object] if StandardError
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

      # Doc setup
      #
      # @note module_function: defines #doc_setup (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] config Docscribe configuration object
      # @param [Hash] opts additional options
      # @return [Object]
      def doc_setup(insertion, config:, **opts)
        node = insertion.node
        name = SourceHelpers.node_name(node)
        return nil unless name

        setup = extract_base_setup(insertion, name)
        resolve_doc_setup!(setup, node, name, config, opts)
      end

      # Build unsafe
      #
      # @note module_function: defines #build_unsafe (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] config Docscribe configuration object
      # @param [Object] setup method setup hash with name, normal_type, scope, visibility
      # @param [Hash] opts additional options including infer_default, fallback_type, treat_options_keyword_as_hash
      # @return [Object]
      def build_unsafe(insertion, config:, setup:, **opts)
        _, pl, rt = build_param_and_raise_info(setup, config, opts)
        lines = build_doc_lines(setup, config: config, insertion: insertion, params_lines: pl, raise_types: rt,
                                       override_tags: opts[:override_tags],
                                       return_description: opts[:return_description],
                                       description: opts[:description])
        lines.map { |l| "#{l}\n" }.join
      end

      # Build param and raise info
      #
      # @note module_function: defines #build_param_and_raise_info (visibility: private)
      # @param [Object] setup method setup hash with name, normal_type, scope, visibility
      # @param [Object] config Docscribe configuration object
      # @param [Object] opts additional options including
      # @return [Array]
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

      # Resolve doc setup
      #
      # @note module_function: defines #resolve_doc_setup! (visibility: private)
      # @param [Object] setup method setup hash with name, normal_type, scope, visibility
      # @param [Object] node AST node whose source text to extract
      # @param [Object] name the method name string
      # @param [Object] config Docscribe configuration object
      # @param [Object] opts additional options including
      # @return [Object]
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

      # Extract base setup
      #
      # @note module_function: defines #extract_base_setup (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] name the method name string
      # @return [Hash]
      def extract_base_setup(insertion, name)
        n = insertion.node
        { node: n, name: name, indent: SourceHelpers.line_indent(n), scope: insertion.scope,
          visibility: insertion.visibility, container: insertion.container,
          method_symbol: insertion.scope == :instance ? '#' : '.' }
      end

      # Resolve external sig
      #
      # @note module_function: defines #resolve_external_sig (visibility: private)
      # @param [Object] container method container name
      # @param [Object] scope method scope symbol
      # @param [Object] name the method name string
      # @param [Object] signature_provider external sig provider
      # @return [Object]
      def resolve_external_sig(container, scope, name, signature_provider)
        signature_provider&.signature_for(container: container, scope: scope, name: name)
      end

      # Compute returns spec
      #
      # @note module_function: defines #compute_returns_spec (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @param [Object] config Docscribe configuration object
      # @param [Object] param_types hash accumulating parameter name-to-type mappings
      # @param [Object] core_rbs_provider RBS type provider
      # @return [Object]
      def compute_returns_spec(node, config, param_types, core_rbs_provider)
        Docscribe::Infer.returns_spec_from_node(
          node, fallback_type: config.fallback_type, nil_as_optional: config.nil_as_optional?,
                param_types: param_types, core_rbs_provider: core_rbs_provider
        )
      end

      # Parse existing doc tags
      #
      # @note module_function: defines #parse_existing_doc_tags (visibility: private)
      # @param [Object] lines existing doc comment lines
      # @return [Boolean] parsed tag info
      def parse_existing_doc_tags(lines)
        init = init_parse_info
        tags_started = false
        joined_lines = join_multiline_tags(Array(lines))
        joined_lines.each_with_object(init) do |line, info|
          extract_all_comment_tags(line, info)
          tags_started = parse_existing_tag_line(line, info, tags_started)
        end
      end

      # Join @param/@return/@raise tag lines where the type bracket spans multiple lines.
      #
      # @note module_function: defines #join_multiline_tags (visibility: private)
      # @param [Object] lines doc comment lines
      # @return [Array]
      def join_multiline_tags(lines)
        result = [] #: Array[String]
        i = 0
        i = consume_tag_or_copy(lines, i, result) while i < lines.length
        result
      end

      # Consume tag line or copy verbatim
      #
      # @note module_function: defines #consume_tag_or_copy (visibility: private)
      # @param [Object] lines doc comment lines
      # @param [Object] idx current line index
      # @param [Object] result result accumulator array
      # @return [Object, Integer]
      def consume_tag_or_copy(lines, idx, result)
        if (c = lines[idx].sub(/^\s*#\s*/, '')) =~ /^@(param|return|raise)\s+\[/ && unbalanced_bracket?(c)
          buffer, consumed = join_tag_continuations(lines, idx)
          result << "# #{buffer}"
          idx + consumed
        else
          result << lines[idx]
          idx + 1
        end
      end

      # Join continuation lines for a multi-line tag type bracket.
      #
      # @note module_function: defines #join_tag_continuations (visibility: private)
      # @param [Object] lines all doc comment lines
      # @param [Object] start index of the @param/@return/@raise line
      # @return [Array] joined content and number of lines consumed
      def join_tag_continuations(lines, start)
        buffer = +lines[start].sub(/^\s*#\s*/, '').dup
        i = start + 1
        while i < lines.length
          continuation = lines[i].sub(/^\s*#[ \t]/, '')
          break unless continuation.start_with?(' ')

          buffer << continuation.rstrip
          i += 1
          break unless unbalanced_bracket?(buffer)
        end
        [buffer, i - start]
      end

      # Check if bracket depth is positive (an opening `[` is unclosed).
      #
      # @note module_function: defines #unbalanced_bracket? (visibility: private)
      # @param [Object] str string to check
      # @return [Boolean]
      def unbalanced_bracket?(str)
        depth = 0
        str.each_char do |c|
          depth += 1 if c == '['
          depth -= 1 if c == ']'
        end
        depth.positive?
      end

      # Parse a single doc comment line for tag info.
      #
      # @note module_function: defines #parse_existing_tag_line (visibility: private)
      # @param [Object] line the doc comment line
      # @param [Object] info mutable parse info accumulator
      # @param [Object] tags_started whether @tags have been seen
      # @return [Object] updated tags_started
      def parse_existing_tag_line(line, info, tags_started)
        content = line.sub(/^\s*# ?/, '').rstrip
        if content.start_with?('@')
          tags_started = true.tap { track_last_tag(content, info) }
          start_note_tag(line, info) if content.start_with?('@note ')
        elsif tags_started && info[:last_tag]
          append_note_continuation(line, info).tap { append_tag_continuation(content, info) }
        else
          info[:description] << content
        end
        tags_started
      end

      # Start a note tag
      #
      # @note module_function: defines #start_note_tag (visibility: private)
      # @param [Object] line doc comment line
      # @param [Object] info parse info hash
      # @return [Object]
      def start_note_tag(line, info)
        return if line.match?(/^\s*#\s*@note\s+module_function:/)

        empty = [] #: Array[String]
        info[:note_lines] << empty
        info[:note_lines].last << line.chomp
      end

      # Append note continuation lines
      #
      # @note module_function: defines #append_note_continuation (visibility: private)
      # @param [Object] line doc comment line
      # @param [Object] info parse info hash
      # @return [Object]
      def append_note_continuation(line, info)
        return unless info[:last_tag] == :note && info[:note_lines].any?

        info[:note_lines].last << line.chomp
      end

      # Init parse info
      #
      # @note module_function: defines #init_parse_info (visibility: private)
      # @return [Hash]
      def init_parse_info
        {
          param_names: {}, param_types: {}, param_descriptions: {},
          raise_types: {}, plugin_tags: {},
          has_return: false, return_type: nil, return_description: nil,
          has_private: false, has_protected: false, has_module_function_note: false,
          description: [],
          last_tag: nil, last_param: nil,
          note_lines: []
        }
      end

      # Merge dest lines
      #
      # @note module_function: defines #merge_dest_lines (visibility: private)
      # @param [Object] existing_lines existing doc comment lines to merge into
      # @param [Hash] ctx merge context hash (setup, insertion, config, info, param_types)
      # @return [Object]
      def merge_dest_lines(existing_lines, **ctx)
        merge_lines_with_context(existing_lines, **ctx)
      end

      # Merge lines with context
      #
      # @note module_function: defines #merge_lines_with_context (visibility: private)
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

      # Build initial line ary
      #
      # @note module_function: defines #build_initial_line_ary (visibility: private)
      # @param [Object] existing_lines existing doc comment lines being merged
      # @param [Object] indent indentation string for the doc line
      # @return [Array]
      def build_initial_line_ary(existing_lines, indent)
        existing_lines.any? && existing_lines.last.strip != '#' ? ["#{indent}#"] : []
      end

      # Merge all tag lines
      #
      # @note module_function: defines #merge_all_tag_lines (visibility: private)
      # @param [Object] base_ary initial line array
      # @param [Hash] ctx context hash with setup, config, info, insertion, param_types
      # @return [self]
      def merge_all_tag_lines(base_ary, **ctx)
        line_ary = base_ary.dup
        merge_tag_lines_core(line_ary, ctx)
        line_ary.concat(merge_rescue_return_lines(ctx[:i], ctx[:s][:rescue_specs], ctx[:config], ctx[:info]))
        line_ary
      end

      # Merge tag lines core
      #
      # @note module_function: defines #merge_tag_lines_core (visibility: private)
      # @param [Object] line_ary output line array
      # @param [Object] ctx merged context hash with info and indent
      # @return [Object]
      def merge_tag_lines_core(line_ary, ctx)
        append_merge_tag_lines(line_ary, ctx)
        merge_return_line(line_ary, ctx[:i], ctx[:s], ctx[:config], ctx[:info])
      end

      # Append merge tag lines
      #
      # @note module_function: defines #append_merge_tag_lines (visibility: private)
      # @param [Object] line_ary output line array
      # @param [Object] ctx merged context hash with info and indent
      # @return [Object]
      def append_merge_tag_lines(line_ary, ctx)
        line_ary.concat(build_all_merge_tags(ctx))
      end

      # Build all merge tags
      #
      # @note module_function: defines #build_all_merge_tags (visibility: private)
      # @param [Object] ctx merged context hash with info and indent
      # @return [Array<Object>]
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

      # Merge return line
      #
      # @note module_function: defines #merge_return_line (visibility: private)
      # @param [Object] line_ary output line array
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with node, name, types, scope
      # @param [Object] config Docscribe configuration object
      # @param [Object] info parse info hash to update with visibility flags
      # @return [Object?]
      def merge_return_line(line_ary, indent, setup, config, info)
        emit_ret = config.emit_return_tag?(setup[:scope], setup[:visibility])
        ret_line = merge_return_tag_line(indent, setup[:normal_type], config: config, scope: setup[:scope],
                                                                      visibility: setup[:visibility], info: info)

        line_ary << ret_line if emit_ret && ret_line
      end

      # Collect all missing
      #
      # @note module_function: defines #collect_all_missing (visibility: private)
      # @param [Object] setup resolved setup hash with node, name, indent, types
      # @param [Object] info parsed existing doc tag information
      # @param [Object] insertion the collected method insertion object
      # @param [Object] config Docscribe configuration object
      # @param [Object] options additional options hash forwarded to missing collector
      # @return [Object]
      def collect_all_missing(setup, info, insertion, config, options)
        s = setup
        ctx = { node: s[:node], indent: s[:indent], config: config, external_sig: s[:external_sig],
                info: info, strategy: options[:strategy], scope: s[:scope], visibility: s[:visibility],
                normal_type: s[:normal_type], rescue_specs: s[:rescue_specs], insertion: insertion,
                param_types: options[:param_types], override_tags: options[:override_tags] }
        collect_missing_all(ctx)
      end

      # Collect missing all
      #
      # @note module_function: defines #collect_missing_all (visibility: private)
      # @param [Object] ctx merged context hash with info and indent
      # @return [Hash]
      def collect_missing_all(ctx)
        lines = [] #: Array[String]
        reasons = [] #: Array[Hash[Symbol, untyped]]
        collect_missing_visibility!(lines, reasons, **ctx)
        collect_missing_module_function_note!(lines, reasons, **ctx)
        collect_missing_params!(lines, reasons, **ctx)
        collect_missing_raises!(lines, reasons, **ctx)
        collect_missing_return!(lines, reasons, **ctx)
        collect_missing_rescue_returns!(lines, reasons, **ctx)
        collect_missing_plugin_tags!(lines, reasons, **ctx)
        { lines: lines, reasons: reasons }
      end

      # Extract param info
      #
      # @note module_function: defines #extract_all_comment_tags (visibility: private)
      # @param [Object] line single comment line
      # @param [Object] info parse info hash
      # @return [Object]
      def extract_all_comment_tags(line, info)
        extract_param_info(line, info[:param_names], info[:param_types], info[:param_descriptions])
        extract_return_info(line, info)
        extract_visibility_info(line, info)
        extract_raise_info(line, info[:raise_types])
        extract_plugin_info(line, info[:plugin_tags])
      end

      # Extract param info from tag line
      #
      # @note module_function: defines #extract_param_info (visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] param_names hash tracking existing @param names
      # @param [Object] param_types hash tracking existing @param types
      # @param [nil] param_descriptions param descriptions hash
      # @return [Object?]
      def extract_param_info(line, param_names, param_types, param_descriptions = nil)
        return unless (pname = extract_param_name_from_param_line(line))

        param_names[pname] = true
        ptype = extract_param_type_from_param_line(line)
        return unless ptype

        param_types[pname] = ptype
        return unless param_descriptions

        desc = extract_param_description(line)
        param_descriptions[pname] = desc if desc
      end

      # Extract return info
      #
      # @note module_function: defines #extract_return_info (visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] info parse info hash to update with return data
      # @return [Object?]
      def extract_return_info(line, info)
        return unless line.match?(/^\s*#\s*@return\b/)

        info[:has_return] = true
        content = line.sub(/^\s*#\s*/, '')
        return unless (m = content.match(/@return\s+/))

        return_type, return_desc = parse_return_rest(m.post_match)
        info[:return_type] = return_type if return_type
        info[:return_description] = return_desc if return_desc
      end

      # Parse return type from rest string
      #
      # @note module_function: defines #parse_return_rest (visibility: private)
      # @param [Object] rest remaining tag content
      # @return [Array]
      def parse_return_rest(rest)
        return unless rest[0] == '['

        type_end = find_matching_close_bracket(rest) or return

        return_type = rest[1...type_end] #: String
        desc = rest[(type_end + 1)..]&.strip
        [return_type, desc&.empty? ? nil : desc]
      end

      # Extract all comment tags from line
      #
      # @note module_function: defines #track_last_tag (visibility: private)
      # @param [Object] content
      # @param [Object] info parse info hash
      # @return [Object?]
      def track_last_tag(content, info)
        tag = content.match(/@(\w+)/)&.[](1)&.to_sym
        info[:last_tag] = tag
        return unless tag == :param

        pname = extract_param_name_from_param_line(content)
        info[:last_param] = pname if pname
      end

      # Append continuation to current tag
      #
      # @note module_function: defines #append_tag_continuation (visibility: private)
      # @param [Object] content tag continuation text
      # @param [Object] info parse info hash
      # @return [Object?]
      def append_tag_continuation(content, info)
        text = content.strip
        return if text.empty?

        append_to_return_description(text, info) if info[:last_tag] == :return
        append_to_param_description(text, info) if info[:last_tag] == :param
      end

      # Append text to return description
      #
      # @note module_function: defines #append_to_return_description (visibility: private)
      # @param [Object] text text to append
      # @param [Object] info parse info hash
      # @return [String, Object]
      def append_to_return_description(text, info)
        if info[:return_description]
          info[:return_description] += "\n#{text}"
        else
          info[:return_description] = text
        end
      end

      # Append text to param description
      #
      # @note module_function: defines #append_to_param_description (visibility: private)
      # @param [Object] text text to append
      # @param [Object] info parse info hash
      # @return [String, Object]
      def append_to_param_description(text, info)
        pname = info[:last_param]
        return unless pname

        if info[:param_descriptions][pname]
          info[:param_descriptions][pname] += "\n#{text}"
        else
          info[:param_descriptions][pname] = text
        end
      end

      # Extract visibility info
      #
      # @note module_function: defines #extract_visibility_info (visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] info parse info hash to update with visibility flags
      # @return [Object]
      def extract_visibility_info(line, info)
        info[:has_private] ||= line.match?(/^\s*#\s*@private\b/)
        info[:has_protected] ||= line.match?(/^\s*#\s*@protected\b/)
        info[:has_module_function_note] ||= line.match?(/^\s*#\s*@note\s+module_function:/)
      end

      # Extract raise info
      #
      # @note module_function: defines #extract_raise_info (visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] raise_types hash tracking existing @raise types
      # @return [Object]
      def extract_raise_info(line, raise_types)
        extract_raise_types_from_line(line).each { |t| raise_types[t || ''] = true }
      end

      # Extract plugin info
      #
      # @note module_function: defines #extract_plugin_info (visibility: private)
      # @param [Object] line a single doc comment line to parse
      # @param [Object] plugin_tags hash tracking existing plugin tag names
      # @return [Object]
      def extract_plugin_info(line, plugin_tags)
        return unless (m = line.match(/^\s*#\s*@(\w+)\b/))

        plugin_tags[m[1] || ''] = true
      end

      # Extract raise types from line
      #
      # @note module_function: defines #extract_raise_types_from_line (visibility: private)
      # @param [Object] line a `@raise` doc line
      # @raise [StandardError]
      # @return [Object, Array] if StandardError
      # @return [Array] if StandardError
      def extract_raise_types_from_line(line)
        return [] unless line.match?(/^\s*#\s*@raise\b/)

        if (m = line.match(/^\s*#\s*@raise\s*\[([^\]]+)\]/))
          parse_raise_bracket_list(m[1]) # steep:ignore ArgumentTypeMismatch
        elsif (m = line.match(/^\s*#\s*@raise\s+([A-Z]\w*(?:::[A-Z]\w*)*)/))
          [m[1]]
        else
          []
        end
      rescue StandardError
        []
      end

      # Parse raise bracket list
      #
      # @note module_function: defines #parse_raise_bracket_list (visibility: private)
      # @param [Object] str comma-separated exception names string from @raise brackets
      # @return [Object] the exception names or nil
      def parse_raise_bracket_list(str)
        str.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      # Build param types from node
      #
      # @note module_function: defines #build_param_types_from_node (visibility: private)
      # @param [Object] node def or defs node
      # @param [Object] external_sig external signature if available
      # @param [Object] config Docscribe configuration object
      # @return [Hash?]
      def build_param_types_from_node(node, external_sig:, config:)
        return unless node

        args = extract_args_from_node(node)
        return unless args

        param_types = {} #: Hash[String, String]
        collect_all_param_types(args, param_types, external_sig, config)
        param_types.empty? ? nil : param_types
      end

      # Collect all param types
      #
      # @note module_function: defines #collect_all_param_types (visibility: private)
      # @param [Object] args arguments AST node
      # @param [Object] param_types hash accumulating parameter name-to-type mappings
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] config Docscribe configuration object
      # @return [Object]
      def collect_all_param_types(args, param_types, external_sig, config)
        # Pre-seed param_types with positional (unnamed) RBS types so that
        # collectors can keep them when external_sig lacks param names.
        positional = Array(external_sig&.positional_types)
        (args.children || []).each_with_index do |a, idx|
          if (ptype = positional[idx])
            pname = a.children.first
            param_types[pname.to_s] = ptype if pname
          end
          collector = PARAM_TYPE_COLLECTORS[a.type]
          collector&.call(a, param_types, external_sig, config)
        end
      end

      # Collect param type
      #
      # @note module_function: defines #collect_param_type (visibility: private)
      # @param [Object] arg_node AST node for the required/keyword argument
      # @param [Object] param_types hash accumulating parameter name-to-type mappings
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] config Docscribe configuration for fallback type options
      # @param [Object] infer_name lambda to transform parameter name for inference
      # @return [Object]
      def collect_param_type(arg_node, param_types, external_sig, config, infer_name:)
        pname = arg_node.children.first.to_s
        param_types[pname] ||= begin
          infer_pname = resolve_infer_name(pname, infer_name)
          external_sig&.param_types&.[](pname) ||
            Infer.infer_param_type(infer_pname, nil,
                                   fallback_type: config.fallback_type,
                                   treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?)
        end
      end

      # Collect optarg param type
      #
      # @note module_function: defines #collect_optarg_param_type (visibility: private)
      # @param [Object] arg_node AST node for the optional/keyword optional argument
      # @param [Object] param_types hash accumulating parameter name-to-type mappings
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] config Docscribe configuration for fallback type options
      # @param [Object] infer_name lambda to transform parameter name for inference
      # @return [Object]
      def collect_optarg_param_type(arg_node, param_types, external_sig, config, infer_name:)
        pname, default = *arg_node
        pname = pname.to_s
        param_types[pname] ||= begin
          default_src = source_from_node(default)
          infer_pname = resolve_infer_name(pname, infer_name)
          external_sig&.param_types&.[](pname) ||
            Infer.infer_param_type(infer_pname, default_src,
                                   fallback_type: config.fallback_type,
                                   treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?)
        end
      end

      # Merge visibility tag lines
      #
      # @note module_function: defines #merge_visibility_tag_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] visibility method visibility symbol
      # @param [Object] config Docscribe configuration object
      # @param [Object] info parse info hash to update with visibility flags
      # @return [Array]
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

      # Merge module function note lines
      #
      # @note module_function: defines #merge_module_function_note_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] insertion the collected method insertion object
      # @param [Object] name the method name string
      # @param [Object] info parse info hash to update with visibility flags
      # @return [Array]
      def merge_module_function_note_lines(indent, insertion, name, info)
        unless insertion.respond_to?(:module_function) && insertion.module_function && !info[:has_module_function_note]
          return []
        end

        included_vis = insertion.included_instance_visibility || :private
        ["#{indent}# @note module_function: defines ##{name} (visibility: #{included_vis})"]
      end

      # Merge param lines
      #
      # @note module_function: defines #merge_param_lines (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @param [Object] indent indentation string for the doc line
      # @param [Object] config Docscribe configuration object
      # @param [Hash] opts additional options including external_sig, param_types, info
      # @return [Object]
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

      # Merge raise tag lines
      #
      # @note module_function: defines #merge_raise_tag_lines (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @param [Object] indent indentation string for the doc line
      # @param [Object] config Docscribe configuration object
      # @param [Object] info parse info hash to update with visibility flags
      # @return [String]
      def merge_raise_tag_lines(node, indent, config, info)
        return [] unless config.emit_raise_tags?

        inferred = Docscribe::Infer.infer_raises_from_node(node)
        existing = info[:raise_types] || {}
        inferred.reject { |rt| existing[rt] }
                .map { |rt| "#{indent}# @raise [#{rt}]" }
      end

      # Merge return tag line
      #
      # @note module_function: defines #merge_return_tag_line (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] normal_type resolved return type
      # @param [Object] config Docscribe configuration object
      # @param [Hash] opts additional options including scope, visibility, info
      # @return [String]
      def merge_return_tag_line(indent, normal_type, config:, **opts)
        return unless config.emit_return_tag?(opts[:scope], opts[:visibility])
        return if opts[:info][:has_return]

        "#{indent}# @return [#{normal_type}]"
      end

      # Merge rescue return lines
      #
      # @note module_function: defines #merge_rescue_return_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] rescue_specs rescue type specs
      # @param [Object] config Docscribe configuration object
      # @param [Object] info parse info hash to update with visibility flags
      # @return [String]
      def merge_rescue_return_lines(indent, rescue_specs, config, info)
        return [] unless config.emit_rescue_conditional_returns?
        return [] if info[:has_return]

        rescue_specs.map do |exceptions, rtype|
          "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
        end
      end

      # Collect missing visibility
      #
      # @note module_function: defines #collect_missing_visibility! (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Hash] ctx merged context hash with info and indent
      # @return [Object]
      def collect_missing_visibility!(lines, reasons, **ctx)
        return unless ctx[:config].emit_visibility_tags?

        add_missing_private(lines, reasons, ctx)
        add_missing_protected(lines, reasons, ctx)
      end

      # Add missing private
      #
      # @note module_function: defines #add_missing_private (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with info and indent
      # @return [Object]
      def add_missing_private(lines, reasons, ctx)
        return unless ctx[:visibility] == :private && !ctx[:info][:has_private]

        lines << "#{ctx[:indent]}# @private\n"
        reasons << { type: :missing_visibility, message: 'missing @private' }
      end

      # Add missing protected
      #
      # @note module_function: defines #add_missing_protected (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with info and indent
      # @return [Object]
      def add_missing_protected(lines, reasons, ctx)
        return unless ctx[:visibility] == :protected && !ctx[:info][:has_protected]

        lines << "#{ctx[:indent]}# @protected\n"
        reasons << { type: :missing_visibility, message: 'missing @protected' }
      end

      # Collect missing module function note
      #
      # @note module_function: defines #collect_missing_module_function_note! (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Hash] ctx merged context hash with info and indent
      # @return [Object]
      def collect_missing_module_function_note!(lines, reasons, **ctx)
        insertion = ctx[:insertion]
        unless insertion.respond_to?(:module_function) && insertion.module_function &&
               !ctx[:info][:has_module_function_note]
          return
        end

        included_vis = insertion.included_instance_visibility || :private
        lines << "#{ctx[:indent]}# @note module_function: defines ##{ctx[:name]} (visibility: #{included_vis})\n"
        reasons << { type: :missing_module_function_note, message: 'missing module_function note' }
      end

      # Collect missing params
      #
      # @note module_function: defines #collect_missing_params! (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Hash] ctx merged context hash with info and indent
      # @return [Object]
      def collect_missing_params!(lines, reasons, **ctx)
        return unless ctx[:config].emit_param_tags?

        all_params = build_params_lines(ctx[:node], ctx[:indent],
                                        external_sig: ctx[:external_sig], config: ctx[:config],
                                        param_types_override: ctx[:param_types])
        return unless all_params

        all_params.each { |pl| collect_param_from_line(pl, lines, reasons, ctx) }
      end

      # Collect param from line
      #
      # @note module_function: defines #collect_param_from_line (visibility: private)
      # @param [Object] param_line a single @param tag line to evaluate
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with build parameters
      # @return [Object, Object?]
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

      # Collect updated param
      #
      # @note module_function: defines #collect_updated_param (visibility: private)
      # @param [Object] param_line a single @param tag line to evaluate
      # @param [Object] pname the parameter name string
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with build parameters
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

      # Build params lines
      #
      # @note module_function: defines #build_params_lines (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @param [Object] indent indentation string for the doc line
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] config Docscribe configuration object
      # @param [Hash] kwargs additional keyword args including insertion, params_lines, raise_types, override_tags
      # @return [Object]
      def build_params_lines(node, indent, external_sig:, config:, **kwargs)
        args = extract_args_from_node(node)
        return nil unless args

        build_all_param_lines(args, indent, config, external_sig: external_sig, **kwargs)
      end

      # Build all param lines
      #
      # @note module_function: defines #build_all_param_lines (visibility: private)
      # @param [Object] args arguments AST node
      # @param [Object] indent indentation string for the doc line
      # @param [Object] config Docscribe configuration object
      # @param [nil] external_sig external method signature for type overrides
      # @param [Hash] kwargs additional keyword args including insertion, params_lines, raise_types, override_tags
      # @return [Object?]
      def build_all_param_lines(args, indent, config, external_sig: nil, **kwargs)
        param_lines = [] #: Array[String]
        params = (args.children || []).each_with_object(param_lines) do |a, p|
          p.concat(build_param_line(a, indent, external_sig, kwargs[:param_types_override],
                                    skip_anonymous_block_params: config.skip_anonymous_block_params?,
                                    fallback_type: config.fallback_type,
                                    treat_options_keyword_as_hash: config.treat_options_keyword_as_hash?,
                                    param_documentation: param_doc_for_arg(a, kwargs, config),
                                    param_tag_style: config.param_tag_style))
        end
        params.empty? ? nil : params
      end

      # Get param doc for argument
      #
      # @note module_function: defines #param_doc_for_arg (visibility: private)
      # @param [Object] arg individual argument node
      # @param [Object] kwargs keyword args hash
      # @param [Object] config doc configuration
      # @return [Object, Object, String]
      def param_doc_for_arg(arg, kwargs, config)
        (kwargs[:param_descriptions] || {})[param_name_from_arg(arg)] ||
          (config.include_param_documentation? ? config.param_documentation : '')
      end

      # Build doc lines
      #
      # @note module_function: defines #build_doc_lines (visibility: private)
      # @param [Object] setup method setup hash with indent, name, types, scope
      # @param [Object] config Docscribe configuration object
      # @param [Hash] kwargs additional keyword args including insertion, params_lines, raise_types, override_tags
      # @return [Object]
      def build_doc_lines(setup, config:, **kwargs)
        i = setup[:indent]
        assemble_doc_lines(i, setup, config: config, insertion: kwargs[:insertion],
                                     params_lines: kwargs[:params_lines],
                                     raise_types: kwargs[:raise_types], override_tags: kwargs[:override_tags],
                                     return_description: kwargs[:return_description],
                                     description: kwargs[:description])
      end

      # Assemble doc lines
      #
      # @note module_function: defines #assemble_doc_lines (visibility: private)
      # @param [Object] indent indent
      # @param [Object] setup setup
      # @param [Hash] ctx context hash with config, insertion, params_lines, raise_types, override_tags
      # @return [Object]
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

      # Append assemble body lines
      #
      # @note module_function: defines #append_assemble_body_lines (visibility: private)
      # @param [Object] line_ary output line array
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, types, scope
      # @param [Object] ctx merged context hash with info and indent
      # @return [Object]
      def append_assemble_body_lines(line_ary, indent, setup, ctx)
        line_ary.concat(build_all_body_tags(indent, setup, ctx))
      end

      # Build all body tags
      #
      # @note module_function: defines #build_all_body_tags (visibility: private)
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, types, scope
      # @param [Object] ctx merged context hash with info and indent
      # @return [Object]
      def build_all_body_tags(indent, setup, ctx)
        result = core_body_tags(indent, setup, ctx)
        result.insert(4, ctx[:params_lines]) if ctx[:params_lines]
        result.flatten
      end

      # Core body tags
      #
      # @note module_function: defines #core_body_tags (visibility: private)
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, types, scope
      # @param [Object] ctx merged context hash with info and indent
      # @return [Array]
      def core_body_tags(indent, setup, ctx)
        config, insertion = ctx.values_at(:config, :insertion)
        [
          defaults_and_visibility(indent, config, setup[:scope], setup[:visibility], description: ctx[:description]),
          build_module_function_note_lines(indent, insertion, setup[:name]),
          ctx.dig(:info, :note_lines) || [],
          build_raise_tag_lines(indent, ctx[:raise_types], config),
          build_return_line_if_needed(indent, setup, config, ctx),
          build_rescue_return_lines(indent, setup[:rescue_specs], config),
          build_plugin_tag_lines(insertion, indent, setup[:normal_type], ctx[:override_tags])
        ]
      end

      # Defaults and visibility
      #
      # @note module_function: defines #defaults_and_visibility (visibility: private)
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] config Docscribe configuration object
      # @param [Object] scope method scope symbol
      # @param [Object] visibility method visibility symbol
      # @param [nil] description optional description lines
      # @return [Array<Object>]
      def defaults_and_visibility(indent, config, scope, visibility, description: nil)
        [
          build_default_msg_lines(indent, config, scope, visibility, description: description),
          build_visibility_tag_lines(indent, visibility, config)
        ].flatten
      end

      # Build return line if needed
      #
      # @note module_function: defines #build_return_line_if_needed (visibility: private)
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] setup method setup hash with name, normal_type, scope, visibility
      # @param [Object] config Docscribe configuration object
      # @param [Object] ctx merged context hash with info and indent
      # @return [Array]
      def build_return_line_if_needed(indent, setup, config, ctx)
        ret_line = build_return_tag_line(indent, setup[:normal_type], config, setup[:scope], setup[:visibility])
        rd = ctx[:return_description]
        if ret_line && rd && !rd.empty?
          lines = rd.split("\n")
          ret_line = +"#{ret_line} #{lines.first}"
          lines[1..]&.each { |l| ret_line << "\n#{indent}#   #{l}" }
        end
        ret_line ? [ret_line] : []
      end

      # Extract args from node
      #
      # @note module_function: defines #extract_args_from_node (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @return [Object]
      def extract_args_from_node(node)
        case node.type
        when :def then node.children[1]
        when :defs then node.children[2]
        end
      end

      # Build param line
      #
      # @note module_function: defines #build_param_line (visibility: private)
      # @param [Object] arg_node AST node for the argument
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Hash] opts additional options for param formatting (fallback_type, param_tag_style, etc.)
      # @return [Array]
      def build_param_line(arg_node, indent, external_sig, param_types_override, **opts)
        method_name = :"build_#{arg_node.type}_line"
        if respond_to?(method_name, true)
          return [] if arg_node.type == :blockarg && opts[:skip_anonymous_block_params] && arg_node.children.first.nil?

          return [send(method_name, arg_node, indent, external_sig, param_types_override, **opts)]
        end

        method_name = :"build_#{arg_node.type}_lines"
        if respond_to?(method_name, true)
          return send(method_name, arg_node, indent, external_sig, param_types_override, **opts)
        end

        []
      end

      # Build header lines
      #
      # @note module_function: defines #build_header_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] config Docscribe configuration object
      # @param [Hash] opts additional options including container, method_symbol, name, normal_type
      # @return [Array]
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

      # Build default msg lines
      #
      # @note module_function: defines #build_default_msg_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] config Docscribe configuration object
      # @param [Object] scope method scope symbol
      # @param [Object] visibility method visibility symbol
      # @param [nil] description optional description lines
      # @return [String, Array]
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

      # Build visibility tag lines
      #
      # @note module_function: defines #build_visibility_tag_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] visibility method visibility symbol
      # @param [Object] config Docscribe configuration object
      # @return [Array]
      def build_visibility_tag_lines(indent, visibility, config)
        return [] unless config.emit_visibility_tags?

        case visibility
        when :private then ["#{indent}# @private"]
        when :protected then ["#{indent}# @protected"]
        else []
        end
      end

      # Build module function note lines
      #
      # @note module_function: defines #build_module_function_note_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] insertion the collected method insertion object
      # @param [Object] name the method name string
      # @return [Array]
      def build_module_function_note_lines(indent, insertion, name)
        return [] unless insertion.respond_to?(:module_function) && insertion.module_function

        included_vis =
          if insertion.respond_to?(:included_instance_visibility) && insertion.included_instance_visibility
            insertion.included_instance_visibility
          else
            :private
          end

        ["#{indent}# @note module_function: defines ##{name} (visibility: #{included_vis})"]
      end

      # Build raise tag lines
      #
      # @note module_function: defines #build_raise_tag_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] raise_types hash tracking existing @raise types
      # @param [Object] config Docscribe configuration object
      # @return [String]
      def build_raise_tag_lines(indent, raise_types, config)
        return [] unless config.emit_raise_tags?

        raise_types.map { |rt| "#{indent}# @raise [#{rt}]" }
      end

      # Build return tag line
      #
      # @note module_function: defines #build_return_tag_line (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] normal_type resolved return type
      # @param [Object] config Docscribe configuration object
      # @param [Object] scope method scope symbol
      # @param [Object] visibility method visibility symbol
      # @return [String]
      def build_return_tag_line(indent, normal_type, config, scope, visibility)
        return unless config.emit_return_tag?(scope, visibility)

        "#{indent}# @return [#{normal_type}]"
      end

      # Build rescue return lines
      #
      # @note module_function: defines #build_rescue_return_lines (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] rescue_specs rescue type specs
      # @param [Object] config Docscribe configuration object
      # @return [String]
      def build_rescue_return_lines(indent, rescue_specs, config)
        return [] unless config.emit_rescue_conditional_returns?

        rescue_specs.map do |exceptions, rtype|
          "#{indent}# @return [#{rtype}] if #{exceptions.join(', ')}"
        end
      end

      # Build plugin tag lines
      #
      # @note module_function: defines #build_plugin_tag_lines (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] indent indentation string for the doc line
      # @param [Object] normal_type resolved return type
      # @param [Object] override_tags plugin tag overrides
      # @return [Object]
      def build_plugin_tag_lines(insertion, indent, normal_type, override_tags)
        plugin_tags = Docscribe::Plugin.run_tag_plugins(build_plugin_context(insertion, normal_type: normal_type))
        plugin_tags.concat(Array(override_tags)) if override_tags
        render_plugin_tags(plugin_tags, indent)
      end

      # Build arg line
      #
      # @note module_function: defines #build_arg_line (visibility: private)
      # @param [Object] arg_node AST node for the required argument
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
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

      # Build optarg lines
      #
      # @note module_function: defines #build_optarg_lines (visibility: private)
      # @param [Object] arg_node AST node for the optional argument
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Hash] opts additional options for param formatting
      # @return [Array]
      def build_optarg_lines(arg_node, indent, external_sig, param_types_override, **opts)
        pname, default = *arg_node
        pname = pname.to_s
        ty = optarg_type(pname, default, external_sig, param_types_override, opts)
        lines = [format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])]

        append_option_lines(lines, default, indent, pname, opts[:fallback_type])
        lines
      end

      # Optarg type
      #
      # @note module_function: defines #optarg_type (visibility: private)
      # @param [Object] pname the parameter name to look up
      # @param [Object] default default value node
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Object] opts additional options including
      # @return [Object]
      def optarg_type(pname, default, external_sig, param_types_override, opts)
        default_src = source_from_node(default)
        lookup_param_type(external_sig, param_types_override, pname, pname,
                          infer_default: default_src,
                          fallback_type: opts[:fallback_type],
                          treat_options_keyword_as_hash: opts[:treat_options_keyword_as_hash])
      end

      # Source from node
      #
      # @note module_function: defines #source_from_node (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @return [Object]
      def source_from_node(node)
        loc = node&.loc
        loc&.expression&.source
      end

      # Resolve infer name
      #
      # @note module_function: defines #resolve_infer_name (visibility: private)
      # @param [Object] pname the parameter name to look up
      # @param [Object] infer_name parameter name string or transformed version for inference
      # @return [Object]
      def resolve_infer_name(pname, infer_name)
        infer_name ? infer_name.call(pname) : pname
      end

      # Build kwarg line
      #
      # @note module_function: defines #build_kwarg_line (visibility: private)
      # @param [Object] arg_node AST node for the keyword argument
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
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

      # Build kwoptarg line
      #
      # @note module_function: defines #build_kwoptarg_line (visibility: private)
      # @param [Object] arg_node AST node for the optional keyword argument
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
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

      # Build restarg line
      #
      # @note module_function: defines #build_restarg_line (visibility: private)
      # @param [Object] arg_node AST node for the rest argument (*args)
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
      def build_restarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = (arg_node.children.first || 'args').to_s
        rest_pos = external_sig&.rest_positional
        ty = if rest_pos&.element_type
               "Array<#{rest_pos.element_type}>"
             else
               lookup_param_type_by_infer(param_types_override, pname, "*#{pname}",
                                          opts[:fallback_type], opts[:treat_options_keyword_as_hash])
             end
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Build kwrestarg line
      #
      # @note module_function: defines #build_kwrestarg_line (visibility: private)
      # @param [Object] arg_node AST node for the keyword rest argument (**kwargs)
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
      # @param [Hash] opts additional options for param formatting
      # @return [Object]
      def build_kwrestarg_line(arg_node, indent, external_sig, param_types_override, **opts)
        pname = (arg_node.children.first || 'kwargs').to_s
        ty = external_sig&.rest_keywords&.type ||
             lookup_param_type_by_infer(param_types_override, pname, "**#{pname}",
                                        opts[:fallback_type], opts[:treat_options_keyword_as_hash])
        format_param_tag(indent, pname, ty, opts[:param_documentation], style: opts[:param_tag_style])
      end

      # Build blockarg line
      #
      # @note module_function: defines #build_blockarg_line (visibility: private)
      # @param [Object] arg_node AST node for the block argument (&block)
      # @param [Object] indent indentation string for doc comment lines
      # @param [Object] external_sig external method signature for type overrides
      # @param [Object] param_types_override map of parameter name to override type
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

      # Lookup param type
      #
      # @note module_function: defines #lookup_param_type (visibility: private)
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

      # Lookup param type by infer
      #
      # @note module_function: defines #lookup_param_type_by_infer (visibility: private)
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
                                 treat_options_keyword_as_hash: treat_options_keyword_as_hash || false)
      end

      # Format param tag
      #
      # @note module_function: defines #format_param_tag (visibility: private)
      # @param [Object] indent indentation string for the doc line
      # @param [Object] name the parameter name
      # @param [Object] type the parameter type string
      # @param [Object] documentation optional documentation text appended to the tag
      # @param [Object] style param tag style (:type_name or :name_type)
      # @return [Object]
      def format_param_tag(indent, name, type, documentation, style:)
        doc = documentation.to_s.strip
        type = type.to_s
        line = build_param_tag_base(indent, name, type, style)
        doc.empty? ? line : append_param_doc(line, doc, indent)
      end

      # Build param tag base string
      #
      # @note module_function: defines #build_param_tag_base (visibility: private)
      # @param [Object] indent indentation string
      # @param [Object] name parameter name
      # @param [Object] type parameter type string
      # @param [Object] style tag style symbol
      # @return [String]
      def build_param_tag_base(indent, name, type, style)
        case style.to_s
        when 'name_type' then "#{indent}# @param #{name} [#{type}]"
        else "#{indent}# @param [#{type}] #{name}"
        end
      end

      # Append param doc text
      #
      # @note module_function: defines #append_param_doc (visibility: private)
      # @param [Object] line existing param tag line
      # @param [Object] doc documentation text
      # @param [Object] indent indentation string
      # @return [Object]
      def append_param_doc(line, doc, indent)
        parts = doc.split("\n")
        result = +"#{line} #{parts.first}"
        parts[1..]&.each { |l| result << "\n#{indent}#   #{l}" }
        result
      end

      # Append option lines
      #
      # @note module_function: defines #append_option_lines (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] default default value node
      # @param [Object] indent indentation string for the doc line
      # @param [Object] pname the parameter name to look up
      # @param [Object] fallback_type default type string when inference fails
      # @return [Object]
      def append_option_lines(lines, default, indent, pname, fallback_type)
        hash_option_pairs(default).each do |pair|
          lines << build_option_line(pair, indent, pname, fallback_type)
        end
      end

      # Hash option pairs
      #
      # @note module_function: defines #hash_option_pairs (visibility: private)
      # @param [Object] node AST node for the default value, expected to be :hash type
      # @return [Array<String>]
      def hash_option_pairs(node)
        return [] unless node&.type == :hash

        node.children.select { |child| child.is_a?(Parser::AST::Node) && child.type == :pair }
      end

      # Build option line
      #
      # @note module_function: defines #build_option_line (visibility: private)
      # @param [Object] pair AST pair node containing key and value
      # @param [Object] indent indentation string for the doc line
      # @param [Object] pname the parent parameter name for @option scope
      # @param [Object] fallback_type default type string when inference fails
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

      # Option key name
      #
      # @note module_function: defines #option_key_name (visibility: private)
      # @param [Object] key_node AST node for the hash key (:sym or :str type)
      # @return [String, Object]
      def option_key_name(key_node)
        case key_node&.type
        when :sym, :str
          key_node.children.first.to_s
        else
          expression = key_node&.loc&.expression
          expression&.source.to_s.sub(/\A:/, '')
        end
      end

      # Node default literal
      #
      # @note module_function: defines #node_default_literal (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @return [Object]
      def node_default_literal(node)
        expression = node&.loc&.expression
        expression&.source
      end

      # Override param type for
      #
      # @note module_function: defines #override_param_type_for (visibility: private)
      # @param [Object] pname the parameter name to look up
      # @param [Object] override_map hash map of parameter name to override type
      # @return [Object]
      def override_param_type_for(pname, override_map)
        return nil unless override_map

        key = pname.to_s
        override_map[key] || override_map[:"#{key}"] || override_map["#{key}:"] || override_map[:"#{key}:"]
      end

      # Extract param description
      #
      # @note module_function: defines #extract_param_description (visibility: private)
      # @param [Object] line a `@param` tag line
      # @return [Object?]
      def extract_param_description(line)
        after = param_rest_after_type(line)
        return nil unless after

        parts = after.split(/\s+/, 2)
        parts[1] if parts.length > 1 && !parts[1].empty?
      end

      # Extract everything after the type bracket in a @param line.
      #
      # @note module_function: defines #param_rest_after_type (visibility: private)
      # @param [Object] line a @param doc line
      # @return [nil] the text after the closing `]`, or nil
      def param_rest_after_type(line)
        content = line.sub(/^\s*#\s*/, '')
        if (m = content.match(/@param\s+(\S+\s+)?\[/))
          brace_end = m.end(0) #: Integer
          rest = content[(brace_end - 1)..] #: String
          type_end = find_matching_close_bracket(rest)
          return rest[(type_end + 1)..]&.strip if type_end
        end
        nil
      end
      ARG_DEFAULT_NAMES = { restarg: 'args', kwrestarg: 'kwargs', blockarg: 'block' }.freeze

      # Param name from arg
      #
      # @note module_function: defines #param_name_from_arg (visibility: private)
      # @param [Object] arg_node AST node for the block argument (&block)
      # @return [Object]
      def param_name_from_arg(arg_node)
        return nil if arg_node.type == :forward_arg

        (arg_node.children.first || ARG_DEFAULT_NAMES[arg_node.type] || '').to_s
      end

      # Extract param name from param line
      #
      # @note module_function: defines #extract_param_name_from_param_line (visibility: private)
      # @param [Object] line a `@param` doc line
      # @return [nil] the parameter name or nil
      def extract_param_name_from_param_line(line)
        content = line.sub(/^\s*#\s*/, '')
        if (m = content.match(/@param\s+(\S+)\s+\[/))
          return m[1]
        elsif (m = content.match(/@param\s+\[/))
          name_end = m.end(0) #: Integer
          rest = content[(name_end - 1)..] #: String
          type_end = find_matching_close_bracket(rest)
          return name_after_type_bracket(rest, type_end) if type_end
        end

        nil
      end

      # Extract name after type bracket
      #
      # @note module_function: defines #name_after_type_bracket (visibility: private)
      # @param [Object] rest tag content after bracket
      # @param [Object] type_end closing bracket position
      # @return [Object]
      def name_after_type_bracket(rest, type_end)
        rest[(type_end + 1)..].to_s.strip.split(/\s+/).first
      end

      # Extract param type from param line
      #
      # @note module_function: defines #extract_param_type_from_param_line (visibility: private)
      # @param [Object] line a `@param` tag line
      # @return [nil]
      def extract_param_type_from_param_line(line)
        content = line.sub(/^\s*#\s*/, '')
        if (m = content.match(/@param\s+(\S+\s+)?\[/))
          name_end = m.end(0) #: Integer
          rest = content[(name_end - 1)..] #: String
          type_end = find_matching_close_bracket(rest)
          return rest[1...type_end] if type_end
        end
        nil
      end

      # Find matching close bracket
      #
      # @note module_function: defines #find_matching_close_bracket (visibility: private)
      # @param [Object] str string to scan
      # @return [nil]
      def find_matching_close_bracket(str)
        depth = 0
        str.each_char.with_index do |c, i|
          case c
          when '[' then depth += 1
          when ']'
            depth -= 1
            return i if depth.zero?
          end
        end
        nil
      end

      # Collect missing raises
      #
      # @note module_function: defines #collect_missing_raises! (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Hash] ctx merged context hash with info and indent
      # @return [Object]
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

      # Collect missing return
      #
      # @note module_function: defines #collect_missing_return! (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Hash] ctx merged context hash with info and indent
      # @return [Object, Object?]
      def collect_missing_return!(lines, reasons, **ctx)
        return unless ctx[:config].emit_return_tag?(ctx[:scope], ctx[:visibility])

        if !ctx[:info][:has_return]
          record_missing_return(lines, reasons, ctx)
        elsif return_type_changed?(ctx)
          record_updated_return(lines, reasons, ctx)
        end
      end

      # Record missing return
      #
      # @note module_function: defines #record_missing_return (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with normal_type and indent
      # @return [Object]
      def record_missing_return(lines, reasons, ctx)
        lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n"
        reasons << { type: :missing_return, message: 'missing @return' }
      end

      # Record updated return
      #
      # @note module_function: defines #record_updated_return (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Object] ctx merged context hash with normal_type and info
      # @return [Object]
      def record_updated_return(lines, reasons, ctx)
        lines << "#{ctx[:indent]}# @return [#{ctx[:normal_type]}]\n" unless ctx[:strategy] == :safe
        reasons << { type: :updated_return,
                     message: "updated @return from #{ctx[:info][:return_type]} to #{ctx[:normal_type]}" }
      end

      # Return type changed
      #
      # @note module_function: defines #return_type_changed? (visibility: private)
      # @param [Object] ctx merged context hash with external_sig, info, and normal_type
      # @return [Object, Boolean]
      def return_type_changed?(ctx)
        ctx[:external_sig] && ctx[:info][:return_type] && ctx[:info][:return_type] != ctx[:normal_type]
      end

      # Collect missing rescue returns
      #
      # @note module_function: defines #collect_missing_rescue_returns! (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Hash] ctx merged context hash with info and indent
      # @return [Object]
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

      # Collect missing plugin tags
      #
      # @note module_function: defines #collect_missing_plugin_tags! (visibility: private)
      # @param [Object] lines array of output doc lines being accumulated
      # @param [Object] reasons array of reason hashes for --explain output
      # @param [Hash] ctx merged context hash with info and indent
      # @return [Object]
      def collect_missing_plugin_tags!(lines, reasons, **ctx)
        plugin_tags = Docscribe::Plugin.run_tag_plugins(build_plugin_context(ctx[:insertion],
                                                                             normal_type: ctx[:normal_type]))
        plugin_tags.concat(Array(ctx[:override_tags])) if ctx[:override_tags]

        plugin_tags.each { |tag| record_plugin_tag(tag, lines, reasons, ctx) }
      end

      # Record plugin tag
      #
      # @note module_function: defines #record_plugin_tag (visibility: private)
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

      # Debug warn
      #
      # @note module_function: defines #debug_warn (visibility: private)
      # @param [Object] error the error that occurred
      # @param [Object] insertion the method insertion being processed
      # @param [Object] name the method name
      # @param [Object] phase the processing phase
      # @return [Object]
      def debug_warn(error, insertion:, name:, phase:)
        return unless debug?

        where = build_debug_location(insertion, name)
        warn "Docscribe DEBUG: #{phase} failed at #{where}: #{error.class}: #{error.message}"
      end

      # Build debug location
      #
      # @note module_function: defines #build_debug_location (visibility: private)
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

      # Debug
      #
      # @note module_function: defines #debug? (visibility: private)
      # @return [Boolean]
      def debug?
        ENV['DOCSCRIBE_DEBUG'] == '1'
      end

      # Build plugin context
      #
      # @note module_function: defines #build_plugin_context (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] normal_type resolved return type
      # @return [Object]
      def build_plugin_context(insertion, normal_type:)
        node = insertion.node
        source = safe_node_source(node)
        new_plugin_context(insertion, node, source, normal_type)
      end

      # New plugin context
      #
      # @note module_function: defines #new_plugin_context (visibility: private)
      # @param [Object] insertion the collected method insertion object
      # @param [Object] node AST node whose source text to extract
      # @param [Object] source method source text
      # @param [Object] normal_type resolved return type
      # @return [Context]
      def new_plugin_context(insertion, node, source, normal_type)
        Docscribe::Plugin::Context.new(
          node: node,
          container: insertion.container,
          scope: insertion.scope,
          visibility: insertion.visibility,
          method_name: SourceHelpers.node_name(node), #: Symbol
          inferred_params: {},
          inferred_return: normal_type,
          source: source
        )
      end

      # Safe node source
      #
      # @note module_function: defines #safe_node_source (visibility: private)
      # @param [Object] node AST node whose source text to extract
      # @raise [StandardError]
      # @return [Object] if StandardError
      # @return [String] if StandardError
      def safe_node_source(node)
        node.loc.expression.source
      rescue StandardError
        ''
      end

      # Render plugin tags
      #
      # @note module_function: defines #render_plugin_tags (visibility: private)
      # @param [Object] tags plugin tag objects
      # @param [Object] indent indentation string for the doc line
      # @return [String]
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
