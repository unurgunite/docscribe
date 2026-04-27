# frozen_string_literal: true

require 'ast'
require 'parser/deprecation'
require 'parser/source/buffer'
require 'parser/source/range'
require 'parser/source/tree_rewriter'

require 'docscribe/config'
require 'docscribe/parsing'

require 'docscribe/inline_rewriter/source_helpers'
require 'docscribe/inline_rewriter/doc_builder'
require 'docscribe/inline_rewriter/collector'
require 'docscribe/inline_rewriter/doc_block'

module Docscribe
  # Raised when source cannot be parsed before rewriting.
  class ParseError < StandardError; end

  # Rewrite Ruby source to insert or update inline YARD-style documentation.
  #
  # Supported strategies:
  # - `:safe`
  #   - insert missing docs
  #   - merge into existing doc-like blocks
  #   - normalize configured sortable tags
  #   - preserve existing prose and directives where possible
  # - `:aggressive`
  #   - replace existing doc blocks with freshly generated docs
  #
  # Compatibility note:
  # - `merge: true` maps to `strategy: :safe`
  # - `rewrite: true` maps to `strategy: :aggressive`
  module InlineRewriter
    class << self
      # Rewrite source and return only the rewritten output string.
      #
      # This is the main convenience entry point for library usage.
      #
      # @param [String] code Ruby source
      # @param [Symbol, nil] strategy :safe or :aggressive
      # @param [Boolean, nil] rewrite compatibility alias for aggressive strategy
      # @param [Boolean, nil] merge compatibility alias for safe strategy
      # @param [Docscribe::Config, nil] config config object (defaults to loaded config)
      # @param [String] file source name used for parser locations/debugging
      # @return [String]
      def insert_comments(code, strategy: nil, rewrite: nil, merge: nil, config: nil, file: '(inline)')
        strategy = normalize_strategy(strategy: strategy, rewrite: rewrite, merge: merge)

        rewrite_with_report(
          code,
          strategy: strategy,
          config: config,
          file: file
        )[:output]
      end

      # Rewrite source and return both output and structured change information.
      #
      # The result hash includes:
      # - `:output`  => rewritten source
      # - `:changes` => structured change records used by CLI explanation output
      #
      # @param [String] code Ruby source
      # @param [Symbol, nil] strategy :safe or :aggressive
      # @param [Boolean, nil] rewrite compatibility alias for aggressive strategy
      # @param [Boolean, nil] merge compatibility alias for safe strategy
      # @param [Docscribe::Config] config config object (defaults to loaded config)
      # @param [String] file source name used for parser locations/debugging
      # @param [nil] core_rbs_provider Param documentation.
      # @raise [Docscribe::ParseError]
      # @raise [StandardError]
      # @return [Hash]
      def rewrite_with_report(code, strategy: nil, rewrite: nil, merge: nil, config: Docscribe::Config.new({}),
                              core_rbs_provider: nil, file: '(inline)')
        strategy = normalize_strategy(strategy: strategy, rewrite: rewrite, merge: merge)
        validate_strategy!(strategy)

        buffer = Parser::Source::Buffer.new(file.to_s, source: code)
        ast = Docscribe::Parsing.parse_buffer(buffer)
        raise Docscribe::ParseError, "Failed to parse #{file}" unless ast

        config ||= Docscribe::Config.load
        signature_provider = build_signature_provider(config, code, file.to_s)
        unless core_rbs_provider
          if config.respond_to?(:core_rbs_provider)
            begin
              core_rbs_provider = config.core_rbs_provider
            rescue StandardError
              core_rbs_provider = nil
            end
          elsif config.respond_to?(:rbs_provider)
            begin
              core_rbs_provider = config.rbs_provider
            rescue StandardError
              core_rbs_provider = nil
            end
          end
        end

        collector = Docscribe::InlineRewriter::Collector.new(buffer)
        collector.process(ast)

        # Collect additional insertions from CollectorPlugins
        plugin_insertions = Docscribe::Plugin.run_collector_plugins(ast, buffer)

        method_insertions = collector.insertions
        attr_insertions = collector.respond_to?(:attr_insertions) ? collector.attr_insertions : []

        all = method_insertions.map { |i| [:method, i] } +
              attr_insertions.map { |i| [:attr, i] } +
              plugin_insertions.map { |i| [:plugin, i] }
        rewriter = Parser::Source::TreeRewriter.new(buffer)
        merge_inserts = Hash.new { |h, k| h[k] = [] }
        changes = []

        all.sort_by { |(kind, ins)| plugin_insertion_pos(kind, ins) }
           .reverse_each do |kind, ins|
          case kind
          when :method
            apply_method_insertion!(
              rewriter: rewriter,
              buffer: buffer,
              insertion: ins,
              config: config,
              signature_provider: signature_provider,
              core_rbs_provider: core_rbs_provider,
              strategy: strategy,
              changes: changes,
              file: file.to_s
            )
          when :attr
            apply_attr_insertion!(
              rewriter: rewriter,
              buffer: buffer,
              insertion: ins,
              config: config,
              signature_provider: signature_provider,
              strategy: strategy,
              merge_inserts: merge_inserts
            )
          when :plugin
            apply_plugin_insertion!(
              rewriter: rewriter,
              buffer: buffer,
              insertion: ins,
              strategy: strategy
            )
          end
        end

        apply_merge_inserts!(rewriter: rewriter, buffer: buffer, merge_inserts: merge_inserts)

        { output: rewriter.process, changes: changes }
      end

      private

      # Resolve the source begin_pos for sorting, handling both Struct-based
      # insertions (method/attr) and Hash-based insertions (plugin).
      #
      # @private
      # @param [Symbol] kind :method, :attr, or :plugin
      # @param [Object] ins insertion object or hash
      # @return [Integer]
      def plugin_insertion_pos(kind, ins)
        case kind
        when :plugin
          ins[:anchor_node].loc.expression.begin_pos
        else
          ins.node.loc.expression.begin_pos
        end
      end

      # Apply one CollectorPlugin insertion according to the selected strategy.
      #
      # :safe       — skip if a doc-like block already exists above anchor_node
      # :aggressive — remove existing doc block, insert fresh
      #
      # @private
      # @param [Parser::Source::TreeRewriter] rewriter
      # @param [Parser::Source::Buffer] buffer
      # @param [Hash] insertion { anchor_node:, doc: }
      # @param [Symbol] strategy
      # @return [void]
      def apply_plugin_insertion!(rewriter:, buffer:, insertion:, strategy:)
        anchor_node = insertion[:anchor_node]
        doc         = insertion[:doc]
        return unless anchor_node && doc && !doc.empty?

        indent = SourceHelpers.line_indent(anchor_node)
        doc    = normalize_plugin_doc_indent(doc, indent)
        bol_range = SourceHelpers.line_start_range(buffer, anchor_node)

        case strategy
        when :aggressive
          # Will remove ANY comments above the method. Plugin will decide what will be changed.
          if (range = any_comment_block_removal_range(buffer, bol_range.begin_pos))
            rewriter.remove(range)
          end
          rewriter.insert_before(bol_range, doc)

        when :safe
          return if SourceHelpers.already_has_doc_immediately_above?(buffer, bol_range.begin_pos)

          rewriter.insert_before(bol_range, doc)
        end
      end

      # Remove any contiguous comment block immediately above anchor_node,
      # regardless of whether it looks like documentation.
      #
      # Used by CollectorPlugin in aggressive mode where the plugin itself
      # is responsible for deciding what to replace.
      #
      # @private
      # @param [Parser::Source::Buffer] buffer
      # @param [Integer] bol_pos beginning-of-line position of anchor_node
      # @return [Parser::Source::Range, nil]
      def any_comment_block_removal_range(buffer, bol_pos)
        src   = buffer.source
        lines = src.lines
        def_line_idx = src[0...bol_pos].count("\n")
        i = def_line_idx - 1

        # Skip blank lines directly above node
        i -= 1 while i >= 0 && lines[i].strip.empty?

        # Nearest non-blank line must be a comment
        return nil unless i >= 0 && lines[i] =~ /^\s*#/

        # Walk upward through the entire contiguous comment block
        start_idx = i
        start_idx -= 1 while start_idx >= 0 && lines[start_idx] =~ /^\s*#/
        start_idx += 1

        # Preserve leading directive-style lines (rubocop, magic comments, etc.)
        removable_start_idx = start_idx
        while removable_start_idx <= i &&
              SourceHelpers.preserved_comment_line?(lines[removable_start_idx])
          removable_start_idx += 1
        end

        return nil if removable_start_idx > i

        start_pos = removable_start_idx.positive? ? lines[0...removable_start_idx].join.length : 0
        Parser::Source::Range.new(buffer, start_pos, bol_pos)
      end

      # Normalise indentation of a plugin-generated doc block.
      #
      # Plugins produce doc strings without knowledge of the surrounding
      # indentation. We strip leading whitespace from each non-empty line
      # and re-prefix it with the indent derived from anchor_node.
      #
      # @private
      # @param [String] doc raw doc string from plugin
      # @param [String] indent indentation prefix to apply
      # @return [String]
      def normalize_plugin_doc_indent(doc, indent)
        doc.lines.map do |line|
          stripped = line.lstrip
          stripped.match?(/\A\r?\n?\z/) ? line : "#{indent}#{stripped}"
        end.join
      end

      # Normalize strategy inputs, including compatibility booleans.
      #
      # Precedence:
      # - explicit `strategy`
      # - `rewrite: true` => `:aggressive`
      # - `merge: true` => `:safe`
      # - default => `:safe`
      #
      # @private
      # @param [Symbol, nil] strategy
      # @param [Boolean, nil] rewrite
      # @param [Boolean, nil] merge
      # @return [Symbol]
      def normalize_strategy(strategy:, rewrite:, merge:)
        return strategy if strategy
        return :aggressive if rewrite
        return :safe if merge

        :safe
      end

      # Validate a normalized rewrite strategy.
      #
      # @private
      # @param [Symbol] strategy
      # @raise [ArgumentError]
      # @return [void]
      def validate_strategy!(strategy)
        return if %i[safe aggressive].include?(strategy)

        raise ArgumentError, "Unknown strategy: #{strategy.inspect}"
      end

      # Apply one method insertion according to the selected strategy.
      #
      # Safe strategy:
      # - merge into existing doc-like blocks when present
      # - otherwise insert a full doc block non-destructively
      #
      # Aggressive strategy:
      # - remove the existing doc block (if any)
      # - insert a fresh regenerated block
      #
      # @private
      # @param [Parser::Source::TreeRewriter] rewriter
      # @param [Parser::Source::Buffer] buffer
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [Docscribe::Config] config
      # @param [Object, nil] signature_provider
      # @param [Symbol] strategy
      # @param [Array<Hash>] changes structured change records
      # @param [String] file
      # @param [Object] core_rbs_provider Param documentation.
      # @return [void]
      def apply_method_insertion!(rewriter:, buffer:, insertion:, config:, signature_provider:, core_rbs_provider:,
                                  strategy:, changes:, file:)
        name = SourceHelpers.node_name(insertion.node)

        return unless config.process_method?(
          container: insertion.container,
          scope: insertion.scope,
          visibility: insertion.visibility,
          name: name
        )

        anchor_bol_range, = method_bol_ranges(buffer, insertion)

        # Create external_sig for param_types lookup
        external_sig = signature_provider&.signature_for(
          container: insertion.container,
          scope: insertion.scope,
          name: SourceHelpers.node_name(insertion.node)
        )

        case strategy
        when :aggressive
          if (range = method_comment_block_removal_range(buffer, insertion))
            rewriter.remove(range)
          end

          doc = build_method_doc(insertion, config: config, signature_provider: signature_provider,
                                            core_rbs_provider: core_rbs_provider, param_types: external_sig&.param_types)
          return if doc.nil? || doc.empty?

          rewriter.insert_before(anchor_bol_range, doc)

          add_change(
            changes,
            type: :insert_full_doc_block,
            insertion: insertion,
            file: file,
            message: 'missing docs'
          )

        when :safe
          info = method_doc_comment_info(buffer, insertion)

          if info
            merge_result = build_missing_method_merge_result(
              insertion,
              existing_lines: info[:doc_lines],
              config: config,
              signature_provider: signature_provider,
              core_rbs_provider: core_rbs_provider,
              param_types: external_sig&.param_types
            )

            missing_lines = merge_result[:lines]
            reason_specs = merge_result[:reasons] || []

            sorted_existing_doc_lines = Docscribe::InlineRewriter::DocBlock.merge(
              info[:doc_lines],
              missing_lines: [],
              sort_tags: config.sort_tags?,
              tag_order: config.tag_order
            )

            merged_doc_lines = Docscribe::InlineRewriter::DocBlock.merge(
              info[:doc_lines],
              missing_lines: missing_lines,
              sort_tags: config.sort_tags?,
              tag_order: config.tag_order
            )

            existing_order_changed = sorted_existing_doc_lines != info[:doc_lines]
            new_block = (info[:preserved_lines] + merged_doc_lines).join
            old_block = info[:lines].join

            if new_block != old_block
              range = Parser::Source::Range.new(buffer, info[:start_pos], info[:end_pos])
              rewriter.replace(range, new_block)

              reason_specs.each do |reason|
                add_change(
                  changes,
                  type: reason[:type],
                  insertion: insertion,
                  file: file,
                  message: reason[:message],
                  extra: reason[:extra] || {}
                )
              end

              if existing_order_changed
                add_change(
                  changes,
                  type: :unsorted_tags,
                  insertion: insertion,
                  file: file,
                  message: 'unsorted tags'
                )
              end
            end

            return
          end

          doc = build_method_doc(insertion, config: config, signature_provider: signature_provider,
                                            core_rbs_provider: core_rbs_provider, param_types: external_sig&.param_types)
          return if doc.nil? || doc.empty?

          rewriter.insert_before(anchor_bol_range, doc)

          add_change(
            changes,
            type: :insert_full_doc_block,
            insertion: insertion,
            file: file,
            message: 'missing docs'
          )
        end
      end

      # Append a structured change record.
      #
      # @private
      # @param [Array<Hash>] changes
      # @param [Symbol] type
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @param [String] file
      # @param [String] message
      # @param [Integer, nil] line
      # @param [Hash] extra
      # @return [void]
      def add_change(changes, type:, insertion:, file:, message:, line: nil, extra: {})
        changes << {
          type: type,
          file: file,
          line: line || method_line_for(insertion),
          method: method_id_for(insertion),
          message: message
        }.merge(extra)
      end

      # Build a printable method identifier from a collected insertion.
      #
      # @private
      # @param [Docscribe::InlineRewriter::Collector::Insertion] insertion
      # @return [String]
      def method_id_for(insertion)
        name = SourceHelpers.node_name(insertion.node)
        "#{insertion.container}#{insertion.scope == :instance ? '#' : '.'}#{name}"
      end

      # Apply one attribute insertion according to the selected strategy.
      #
      # @private
      # @param [Parser::Source::TreeRewriter] rewriter
      # @param [Parser::Source::Buffer] buffer
      # @param [Docscribe::InlineRewriter::Collector::AttrInsertion] insertion
      # @param [Docscribe::Config] config
      # @param [Object, nil] signature_provider
      # @param [Symbol] strategy
      # @param [Hash] merge_inserts
      # @return [void]
      def apply_attr_insertion!(rewriter:, buffer:, insertion:, config:, signature_provider:, strategy:, merge_inserts:)
        return unless config.respond_to?(:emit_attributes?) && config.emit_attributes?
        return unless attribute_allowed?(config, insertion)

        bol_range = SourceHelpers.line_start_range(buffer, insertion.node)

        case strategy
        when :aggressive
          if (range = SourceHelpers.comment_block_removal_range(buffer, bol_range.begin_pos))
            rewriter.remove(range)
          end

          doc = build_attr_doc_for_node(
            insertion,
            config: config,
            signature_provider: signature_provider
          )
          return if doc.nil? || doc.empty?

          rewriter.insert_before(bol_range, doc)

        when :safe
          info = SourceHelpers.doc_comment_block_info(buffer, bol_range.begin_pos)

          if info
            additions = build_attr_merge_additions(
              insertion,
              existing_lines: info[:lines],
              config: config,
              signature_provider: signature_provider
            )

            if additions && !additions.empty?
              merge_inserts[info[:end_pos]] << [insertion.node.loc.expression.begin_pos, additions]
            end

            return
          end

          doc = build_attr_doc_for_node(
            insertion,
            config: config,
            signature_provider: signature_provider
          )
          return if doc.nil? || doc.empty?

          rewriter.insert_before(bol_range, doc)
        end
      end

      # Apply aggregated merge inserts at shared end positions.
      #
      # Used primarily for attribute merge behavior where multiple additions may target the same block end.
      #
      # @private
      # @param [Parser::Source::TreeRewriter] rewriter
      # @param [Parser::Source::Buffer] buffer
      # @param [Hash{Integer=>Array<(Integer,String)>}] merge_inserts
      # @return [void]
      def apply_merge_inserts!(rewriter:, buffer:, merge_inserts:)
        sep_re = /^\s*#\s*\r?\n$/

        merge_inserts.keys.sort.reverse_each do |end_pos|
          chunks = merge_inserts[end_pos]
          next if chunks.empty?

          chunks = chunks.sort_by { |(sort_key, _s)| sort_key }

          out_lines = []

          chunks.each do |(_k, chunk)|
            next if chunk.nil? || chunk.empty?

            lines = chunk.lines
            seps = []
            seps << lines.shift while !lines.empty? && lines.first.match?(sep_re)

            sep = seps.first
            out_lines << sep if sep && (out_lines.empty? || !out_lines.last.match?(sep_re))
            out_lines.concat(lines)
          end

          text = out_lines.join
          next if text.empty?

          range = Parser::Source::Range.new(buffer, end_pos, end_pos)
          rewriter.insert_before(range, text)
        end
      end

      # Build plain-text merge additions for an attribute doc block.
      #
      # @private
      # @param [Docscribe::InlineRewriter::Collector::AttrInsertion] ins
      # @param [Array<String>] existing_lines
      # @param [Docscribe::Config] config
      # @param [Object] signature_provider Param documentation.
      # @raise [StandardError]
      # @return [String, nil]
      def build_attr_merge_additions(ins, existing_lines:, config:, signature_provider:)
        indent = SourceHelpers.line_indent(ins.node)
        param_tag_style = config.param_tag_style
        existing = existing_attr_names(existing_lines)
        missing = ins.names.reject { |name_sym| existing[name_sym.to_s] }
        return '' if missing.empty?

        lines = []
        lines << "#{indent}#" if existing_lines.any? && existing_lines.last.strip != '#'

        missing.each_with_index do |name_sym, idx|
          attr_name = name_sym.to_s
          mode = ins.access.to_s
          attr_type = attribute_type(ins, name_sym, config, signature_provider: signature_provider)

          lines << "#{indent}# @!attribute [#{mode}] #{attr_name}"

          if config.emit_visibility_tags?
            lines << "#{indent}# @private" if ins.visibility == :private
            lines << "#{indent}# @protected" if ins.visibility == :protected
          end

          lines << "#{indent}#   @return [#{attr_type}]" if %i[r rw].include?(ins.access)
          if %i[w rw].include?(ins.access)
            lines << format_attribute_param_tag(indent, 'value', attr_type, style: param_tag_style)
          end
          lines << "#{indent}#" if idx < missing.length - 1
        end

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      # Extract already documented attribute names from existing `@!attribute` lines.
      #
      # @private
      # @param [Array<String>] lines
      # @return [Hash{String=>Boolean}]
      def existing_attr_names(lines)
        names = {}

        Array(lines).each do |line|
          if (m = line.match(/^\s*#\s*@!attribute\b(?:\s+\[[^\]]+\])?\s+(\S+)/))
            names[m[1]] = true
          end
        end

        names
      end

      # Decide whether an attribute macro should be emitted according to method filters.
      #
      # @private
      # @param [Docscribe::Config] config
      # @param [Docscribe::InlineRewriter::Collector::AttrInsertion] ins
      # @return [Boolean]
      def attribute_allowed?(config, ins)
        ins.names.any? do |name_sym|
          ok = false

          if %i[r rw].include?(ins.access)
            ok ||= config.process_method?(
              container: ins.container,
              scope: ins.scope,
              visibility: ins.visibility,
              name: name_sym
            )
          end

          if %i[w rw].include?(ins.access)
            ok ||= config.process_method?(
              container: ins.container,
              scope: ins.scope,
              visibility: ins.visibility,
              name: :"#{name_sym}="
            )
          end

          ok
        end
      end

      # Build a full `@!attribute` documentation block for one attribute insertion.
      #
      # @private
      # @param [Docscribe::InlineRewriter::Collector::AttrInsertion] ins
      # @param [Docscribe::Config] config
      # @param [Object] signature_provider Param documentation.
      # @raise [StandardError]
      # @return [String, nil]
      def build_attr_doc_for_node(ins, config:, signature_provider:)
        indent = SourceHelpers.line_indent(ins.node)
        param_tag_style = config.param_tag_style
        lines = []

        ins.names.each_with_index do |name_sym, idx|
          attr_name = name_sym.to_s
          mode = ins.access.to_s
          attr_type = attribute_type(ins, name_sym, config, signature_provider: signature_provider)

          lines << "#{indent}# @!attribute [#{mode}] #{attr_name}"

          if config.emit_visibility_tags?
            lines << "#{indent}# @private" if ins.visibility == :private
            lines << "#{indent}# @protected" if ins.visibility == :protected
          end

          lines << "#{indent}#   @return [#{attr_type}]" if %i[r rw].include?(ins.access)
          if %i[w rw].include?(ins.access)
            lines << format_attribute_param_tag(indent, 'value', attr_type, style: param_tag_style)
          end

          lines << "#{indent}#" if idx < ins.names.length - 1
        end

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      # Format an attribute `@param` tag line using the configured param tag style.
      #
      # @private
      # @param [String] indent leading whitespace
      # @param [Symbol] name attribute name
      # @param [String] type attribute type
      # @param [String, Symbol] style param tag style (`"name_type"` or `"type_name"`)
      # @return [String] formatted doc line
      def format_attribute_param_tag(indent, name, type, style:)
        type = type.to_s

        case style.to_s
        when 'name_type'
          "#{indent}#   @param #{name} [#{type}]"
        else
          "#{indent}#   @param [#{type}] #{name}"
        end
      end

      # Determine the attribute type for one attr name.
      #
      # Prefers the RBS reader signature when available; otherwise falls back to the config fallback type.
      #
      # @private
      # @param [Docscribe::InlineRewriter::Collector::AttrInsertion] ins
      # @param [Symbol] name_sym
      # @param [Docscribe::Config] config
      # @param [Object] signature_provider Param documentation.
      # @raise [StandardError]
      # @return [String]
      def attribute_type(ins, name_sym, config, signature_provider:)
        ty = config.fallback_type
        return ty unless signature_provider

        reader_sig = signature_provider.signature_for(container: ins.container, scope: ins.scope, name: name_sym)
        reader_sig&.return_type || ty
      rescue StandardError
        config.fallback_type
      end

      # Build the appropriate external signature provider for the given source.
      #
      # Checks config methods in order: `signature_provider_for`, `signature_provider`, `rbs_provider`.
      #
      # @private
      # @param [Docscribe::Config] config the active configuration
      # @param [String] code the source code being processed
      # @param [String] file the file name
      # @raise [StandardError]
      # @return [Object, nil] a signature provider or nil
      def build_signature_provider(config, code, file)
        if config.respond_to?(:signature_provider_for)
          config.signature_provider_for(source: code, file: file)
        elsif config.respond_to?(:signature_provider)
          config.signature_provider
        elsif config.respond_to?(:rbs_provider)
          config.rbs_provider
        end
      rescue StandardError
        config.respond_to?(:rbs_provider) ? config.rbs_provider : nil
      end

      # Delegate to DocBuilder.build for generating a complete doc block.
      #
      # @private
      # @param [Collector::Insertion] insertion the collected method insertion
      # @param [Docscribe::Config] config the active configuration
      # @param [Object, nil] signature_provider external signature provider
      # @param [Object, nil] core_rbs_provider RBS core type provider
      # @param [Hash, nil] param_types parameter name -> type map
      # @return [String, nil] generated doc block or nil
      def build_method_doc(insertion, config:, signature_provider:, core_rbs_provider:, param_types:)
        DocBuilder.build(
          insertion,
          config: config,
          signature_provider: signature_provider,
          core_rbs_provider: core_rbs_provider,
          param_types: param_types
        )
      end

      # Delegate to DocBuilder.build_missing_merge_result for generating missing doc lines only.
      #
      # @private
      # @param [Collector::Insertion] insertion the collected method insertion
      # @param [Array<String>] existing_lines existing doc-like lines
      # @param [Docscribe::Config] config the active configuration
      # @param [Object, nil] signature_provider external signature provider
      # @param [Object, nil] core_rbs_provider RBS core type provider
      # @param [Hash, nil] param_types parameter name -> type map
      # @return [Hash] result with `:lines` and `:reasons` keys
      def build_missing_method_merge_result(insertion, existing_lines:, config:, signature_provider:,
                                            core_rbs_provider:, param_types:)
        DocBuilder.build_missing_merge_result(
          insertion,
          existing_lines: existing_lines,
          config: config,
          signature_provider: signature_provider,
          core_rbs_provider: core_rbs_provider,
          param_types: param_types
        )
      end

      # Get doc comment block info (preceding comments) for a method insertion.
      #
      # @private
      # @param [Parser::Source::Buffer] buffer the source buffer
      # @param [Collector::Insertion] insertion the collected method insertion
      # @return [Hash, nil] doc comment block info or nil
      def method_doc_comment_info(buffer, insertion)
        anchor_bol_range, def_bol_range = method_bol_ranges(buffer, insertion)

        SourceHelpers.doc_comment_block_info(buffer, anchor_bol_range.begin_pos) ||
          SourceHelpers.doc_comment_block_info(buffer, def_bol_range.begin_pos)
      end

      # Find the range of an existing doc comment block to remove (aggressive mode).
      #
      # @private
      # @param [Parser::Source::Buffer] buffer the source buffer
      # @param [Collector::Insertion] insertion the collected method insertion
      # @return [Parser::Source::Range, nil]
      def method_comment_block_removal_range(buffer, insertion)
        anchor_bol_range, def_bol_range = method_bol_ranges(buffer, insertion)

        SourceHelpers.comment_block_removal_range(buffer, anchor_bol_range.begin_pos) ||
          SourceHelpers.comment_block_removal_range(buffer, def_bol_range.begin_pos)
      end

      # Get the beginning-of-line ranges for the anchor and method nodes.
      #
      # @private
      # @param [Parser::Source::Buffer] buffer the source buffer
      # @param [Collector::Insertion] insertion the collected method insertion
      # @return [Array<Parser::Source::Range>]
      def method_bol_ranges(buffer, insertion)
        anchor_node = anchor_node_for(insertion)
        [
          SourceHelpers.line_start_range(buffer, anchor_node),
          SourceHelpers.line_start_range(buffer, insertion.node)
        ]
      end

      # Get the source line number for the method's anchor node.
      #
      # @private
      # @param [Collector::Insertion] insertion the collected method insertion
      # @raise [StandardError]
      # @return [Integer] the 1-based line number
      def method_line_for(insertion)
        anchor_node_for(insertion).loc.expression.line
      rescue StandardError
        insertion.node.loc.expression.line
      end

      # Get the anchor node for an insertion (Sorbet `sig` or the method node itself).
      #
      # @private
      # @param [Collector::Insertion] insertion the collected method insertion
      # @return [Parser::AST::Node]
      def anchor_node_for(insertion)
        if insertion.respond_to?(:anchor_node) && insertion.anchor_node
          insertion.anchor_node
        else
          insertion.node
        end
      end
    end
  end
end
