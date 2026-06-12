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
      # @param [Hash] options additional keyword arguments forwarded to rewrite_with_report
      # @return [String]
      def insert_comments(code, strategy: nil, rewrite: nil, merge: nil, **options)
        strategy = normalize_strategy(strategy: strategy, rewrite: rewrite, merge: merge)

        rewrite_with_report(code, strategy: strategy, **options)[:output]
      end

      # Rewrite source and return both output and structured change information.
      #
      # @param [String] code Ruby source
      # @param [Symbol, nil] strategy :safe or :aggressive
      # @param [Boolean, nil] rewrite compatibility alias for aggressive strategy
      # @param [Boolean, nil] merge compatibility alias for safe strategy
      # @param [Hash] **options remaining options (config:, file:, core_rbs_provider:)
      # @param [Hash] options additional keyword arguments forwarded to downstream helpers
      # @raise [Docscribe::ParseError]
      # @raise [StandardError]
      # @return [Hash]
      def rewrite_with_report(code, strategy: nil, rewrite: nil, merge: nil, **options)
        strategy = normalize_strategy(strategy: strategy, rewrite: rewrite, merge: merge)
        validate_strategy!(strategy)
        parsed = setup_rewrite_env(code, options)
        pipeline = build_rewrite_pipeline(parsed[:buffer], parsed[:ast])
        dispatch_rewrite_insertions(pipeline, parsed[:buffer],
                                    config: parsed[:config], signature_provider: parsed[:signature_provider],
                                    core_rbs_provider: parsed[:core_rbs_provider], strategy: strategy,
                                    file: parsed[:file])
        { output: pipeline[:rewriter].process, changes: pipeline[:changes] }
      end

      # Build the insertion pipeline: collector, plugin insertions, dedup, rewriter, merge_inserts, changes.
      #
      # @param [Object] buffer the source buffer being rewritten
      # @param [Object] ast the parsed AST of the source code
      # @return [Hash]
      def build_rewrite_pipeline(buffer, ast)
        all = collect_insertions(buffer, ast)
        method_overrides_by_pos = {} #: Hash[Integer, untyped]
        all = deduplicate_insertions(all, method_overrides_by_pos: method_overrides_by_pos)
        rewriter = Parser::Source::TreeRewriter.new(buffer)
        merge_inserts = Hash.new { |h, k| h[k] = [] } #: Hash[Integer, untyped]
        changes = [] #: Array[untyped]

        { all: all, method_overrides_by_pos: method_overrides_by_pos, rewriter: rewriter,
          merge_inserts: merge_inserts, changes: changes }
      end

      # Dispatch all insertions to the appropriate handler.
      #
      # @param [Object] pipeline the pipeline hash with rewriter, insertions, and tracking state
      # @param [Object] buffer the source buffer being rewritten
      # @param [Hash] options additional kwargs (config, signature_provider, core_rbs_provider, strategy, file)
      # @return [Object]
      def dispatch_rewrite_insertions(pipeline, buffer, **options)
        pipeline[:all].sort_by { |(kind, ins)| plugin_insertion_pos(kind, ins) }
                      .reverse_each do |kind, ins|
          case kind
          when :method then dispatch_method_insertion(ins, pipeline, buffer, **options)
          when :attr then dispatch_attr_insertion(ins, pipeline, buffer, **options)
          when :plugin then dispatch_plugin_insertion(ins, pipeline, buffer, **options)
          end
        end

        apply_merge_inserts!(rewriter: pipeline[:rewriter], buffer: buffer, merge_inserts: pipeline[:merge_inserts])
      end

      # Dispatch a method insertion.
      #
      # @private
      # @param [Object] ins
      # @param [Hash] pipeline
      # @param [Object] buffer
      # @param [Hash] options
      # @return [void]
      def dispatch_method_insertion(ins, pipeline, buffer, **options)
        pos = plugin_insertion_pos(:method, ins)
        method_override = pipeline[:method_overrides_by_pos][pos]

        apply_method_insertion!(
          rewriter: pipeline[:rewriter], buffer: buffer, insertion: ins,
          config: options[:config], signature_provider: options[:signature_provider],
          core_rbs_provider: options[:core_rbs_provider], strategy: options[:strategy],
          changes: pipeline[:changes], file: options[:file],
          method_override: method_override
        )
      end

      # Dispatch an attr insertion.
      #
      # @private
      # @param [Object] ins
      # @param [Hash] pipeline
      # @param [Object] buffer
      # @param [Hash] options
      # @return [void]
      def dispatch_attr_insertion(ins, pipeline, buffer, **options)
        apply_attr_insertion!(
          rewriter: pipeline[:rewriter], buffer: buffer, insertion: ins,
          config: options[:config], signature_provider: options[:signature_provider],
          strategy: options[:strategy], merge_inserts: pipeline[:merge_inserts]
        )
      end

      # Dispatch a plugin insertion.
      #
      # @private
      # @param [Object] ins
      # @param [Hash] pipeline
      # @param [Object] buffer
      # @param [Hash] options
      # @return [void]
      def dispatch_plugin_insertion(ins, pipeline, buffer, **options)
        apply_plugin_insertion!(
          rewriter: pipeline[:rewriter], buffer: buffer, insertion: ins,
          strategy: options[:strategy], config: options[:config]
        )
      end

      private

      # Setup the parsing environment for rewrite_with_report.
      # @private
      # @param [Object] code the Ruby source code string to parse and rewrite
      # @param [Object] options hash containing :config, :file, and :core_rbs_provider
      # @raise [Docscribe::ParseError]
      # @return [Hash]
      def setup_rewrite_env(code, options)
        config = options[:config] || Docscribe::Config.load
        file = (options[:file] || '(inline)').to_s
        core_rbs_provider = options[:core_rbs_provider]
        buffer = Parser::Source::Buffer.new(file, source: code)
        ast = Docscribe::Parsing.parse_buffer(buffer)
        raise Docscribe::ParseError, "Failed to parse #{file}" unless ast

        { config: config, file: file, buffer: buffer, ast: ast,
          signature_provider: build_signature_provider(config, code, file),
          core_rbs_provider: load_core_rbs_provider(config, core_rbs_provider) }
      end

      # Load core RBS provider from config with safe fallback.
      #
      # @private
      # @param [Object] config the active Docscribe::Config
      # @param [Object] core_rbs_provider optional externally-provided core RBS provider
      # @raise [StandardError]
      # @return [Object]
      # @return [nil] if StandardError
      def load_core_rbs_provider(config, core_rbs_provider)
        core_rbs_provider || (config.respond_to?(:core_rbs_provider) ? config.core_rbs_provider : nil)
      rescue StandardError => e
        warn "Docscribe: failed to load core RBS provider: #{e.message}" if ENV.fetch('DOCSCRIBE_DEBUG', false)
        nil
      end

      # Collect insertions from collector and plugins into a combined list.
      # @private
      # @param [Object] buffer the source buffer to collect insertions from
      # @param [Object] ast the parsed AST to traverse for collection
      # @return [Object]
      def collect_insertions(buffer, ast)
        collector = Docscribe::InlineRewriter::Collector.new(buffer)
        collector.process(ast)
        plugin_insertions = Docscribe::Plugin.run_collector_plugins(ast, buffer)
        method_insertions = collector.insertions
        attr_insertions = collector.respond_to?(:attr_insertions) ? collector.attr_insertions : [] #: Array[untyped]
        method_insertions.map { |i| [:method, i] } +
          attr_insertions.map { |i| [:attr, i] } +
          plugin_insertions.map { |i| [:plugin, i] }
      end

      # Deduplicate insertions by source position.
      #
      # Rules:
      # 1. Plugin insertions override method insertions at the same position
      #    (CollectorPlugin knows more than the standard collector for that node).
      # 2. If multiple CollectorPlugins target the same position, only insertions
      # from the highest priority plugin(s) are kept (ties are kept).
      # 3. Multiple plugin insertions at the same position are allowed
      # (a single plugin may generate multiple doc blocks, e.g. one per column).
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] insertions tagged insertion list
      # @param [nil] method_overrides_by_pos method-level overrides keyed by insertion position
      # @return [Array<Array(Symbol,Object)>]
      def deduplicate_insertions(insertions, method_overrides_by_pos: nil)
        group_by_position(insertions).each_with_object([]) do |(pos, items), result|
          process_dedup_group(pos, items, result, method_overrides_by_pos)
        end
      end

      # Process one group of deduplication at a given position.
      # @private
      # @param [Object] pos the source begin_pos for the group
      # @param [Object] items all [kind, insertion] pairs at this position
      # @param [Object] result the accumulator array for surviving insertions
      # @param [Object] method_overrides_by_pos hash mapping position to method override data
      # @return [Object]
      def process_dedup_group(pos, items, result, method_overrides_by_pos)
        plugin_items = items.select { |pair| pair.first == :plugin }
        return result.concat(items) if plugin_items.empty?

        method_items = items.select { |pair| pair.first == :method }
        override_items = find_override_items(plugin_items)
        if override_items.any? && method_items.any?
          handle_override_case(result, items, override_items, method_overrides_by_pos, pos)
        else
          result.concat(deduplicate_items(items, plugin_items, pos, method_items))
        end
      end

      # Group insertions by their source position.
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] insertions
      # @return [Hash{Integer => Array<Array(Symbol,Object)>}]
      def group_by_position(insertions)
        groups = {} #: Hash[Integer, untyped]
        insertions.each do |kind, ins|
          pos = plugin_insertion_pos(kind, ins)
          (groups[pos] ||= []) << [kind, ins]
        end
        groups
      end

      # Find plugin items that have a method_override hash.
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] plugin_items
      # @return [Array<Array(Symbol,Object)>]
      def find_override_items(plugin_items)
        plugin_items.select do |_k, ins|
          ins.is_a?(Hash) && ins[:method_override].is_a?(Hash)
        end
      end

      # Handle a method_override case: record the winning override and remove override items.
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] result
      # @param [Array<Array(Symbol,Object)>] items
      # @param [Array<Array(Symbol,Object)>] override_items
      # @param [Hash, nil] method_overrides_by_pos
      # @param [Integer] pos
      # @return [Object]
      def handle_override_case(result, items, override_items, method_overrides_by_pos, pos)
        if method_overrides_by_pos
          winning_ins = pick_highest_priority_override_insertion(override_items, pos: pos)
          method_overrides_by_pos[pos] = winning_ins[:method_override] if winning_ins
        end

        items = items.reject { |k, ins| k == :plugin && ins.is_a?(Hash) && ins.key?(:method_override) }
        result.concat(items)
      end

      # Handle items where no method_override applies (plugin-doc case or fallback).
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] items
      # @param [Array<Array(Symbol,Object)>] plugin_items
      # @param [Integer] pos
      # @param [Object] _method_items method insertion pairs at this position (unused)
      # @return [Array<Array(Symbol,Object)>]
      def deduplicate_items(items, plugin_items, pos, _method_items)
        plugin_doc_items = plugin_items.select { |pair| plugin_doc_item?(pair) }

        if plugin_doc_items.any?
          deduplicate_plugin_doc_case(items, plugin_doc_items, pos)
        else
          items.reject { |pair| override_or_plugin_method?(pair) }
        end
      end

      # Predicate: insertion pair has a doc key with non-empty content.
      # @private
      # @param [Object] pair the [kind, insertion] tuple to inspect
      # @return [Object]
      def plugin_doc_item?(pair)
        _k, ins = pair
        ins.is_a?(Hash) && ins[:doc] && !ins[:doc].empty?
      end

      # Deduplicate plugin doc items, keeping only highest-priority entries.
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] items
      # @param [Array<Array(Symbol,Object)>] plugin_doc_items
      # @param [Integer] pos
      # @return [Array<Array(Symbol,Object)>]
      def deduplicate_plugin_doc_case(items, plugin_doc_items, pos)
        items = items.reject { |k, _| k == :method }
        items = items.reject { |pair| override_or_plugin_method?(pair) }

        max_prio = max_plugin_priority(plugin_doc_items)
        dropped = filter_lower_priority_plugins(items, max_prio)
        items = items.reject { |k, ins| dropped.include?([k, ins]) }

        warn_plugin_conflict!(dropped, plugin_doc_items, max_prio, pos) if Docscribe::Plugin.debug? && dropped.any?

        items
      end

      # Predicate: insertion pair is a plugin with method_override.
      # @private
      # @param [Object] pair the [kind, insertion] tuple to inspect
      # @return [Object]
      def override_or_plugin_method?(pair)
        k, ins = pair
        k == :plugin && ins.is_a?(Hash) && ins.key?(:method_override)
      end

      # Find the maximum priority among plugin doc items.
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] plugin_items
      # @return [Integer]
      def max_plugin_priority(plugin_items)
        plugin_items.map { |_k, ins| plugin_insertion_priority(ins) }.max || 0
      end

      # Filter plugin items that fall below the given priority threshold.
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] items
      # @param [Integer] threshold
      # @return [Array<Array(Symbol,Object)>]
      def filter_lower_priority_plugins(items, threshold)
        items.select do |k, ins|
          k == :plugin && ins.is_a?(Hash) && ins[:doc] && plugin_insertion_priority(ins) < threshold
        end
      end

      # Warn about conflicting collector plugins at a given position.
      #
      # @private
      # @param [Array<Array(Symbol,Object)>] dropped
      # @param [Array<Array(Symbol,Object)>] plugin_items
      # @param [Integer] max_prio
      # @param [Integer] pos
      # @return [Object]
      def warn_plugin_conflict!(dropped, plugin_items, max_prio, pos)
        kept_labels = plugin_items.map { |_k, ins| plugin_insertion_label(ins) }.uniq
        dropped_labels = dropped.map { |_k, ins| plugin_insertion_label(ins) }.uniq
        loc = conflict_location_str(pos, plugin_items)
        warn "Docscribe: CollectorPlugin conflict at #{loc} — " \
             "#{dropped_labels.join(', ')} (pri=#{dropped.map { |_k, ins| plugin_insertion_priority(ins) }.max}) " \
             "dropped in favor of #{kept_labels.join(', ')} (pri=#{max_prio}). " \
             'Set explicit priority or adjust anchor_node to avoid collision.'
      end

      # Build a human-readable location string for a conflict warning.
      # @private
      # @param [Object] pos the source position of the conflict
      # @param [Object] plugin_items the plugin insertion pairs involved in the conflict
      # @return [Object]
      def conflict_location_str(pos, plugin_items)
        line = plugin_insertion_line(plugin_items.first[1])
        loc = +"pos=#{pos}"
        loc << " line=#{line}" if line
        loc
      end

      # @private
      # @param override_items [Array<Array(Symbol, Hash)>] list of [:plugin, insertion_hash]
      #   that include :method_override
      # @param pos [Integer] begin_pos (used only for debug output)
      # @return [Hash, nil] winning insertion hash (the one whose override will be applied)
      def pick_highest_priority_override_insertion(override_items, pos:)
        return nil if override_items.empty?

        max_prio = max_plugin_priority_for(override_items)
        winners  = override_items.select { |_k, ins| plugin_insertion_priority(ins) == max_prio }
        winners_sorted = sort_winners_by_order(winners)

        warn_override_conflict!(winners_sorted, max_prio, pos)

        winners_sorted.first[1]
      end

      # Compute max priority among override items.
      # @private
      # @param [Object] override_items plugin insertion pairs containing :method_override
      # @return [Object]
      def max_plugin_priority_for(override_items)
        override_items.map { |_k, ins| plugin_insertion_priority(ins) }.max || 0
      end

      # Sort override winners deterministically by plugin order.
      # @private
      # @param [Object] winners override insertion pairs tied at the highest priority
      # @return [Object]
      def sort_winners_by_order(winners)
        winners.sort_by do |_k, ins|
          order = ins.is_a?(Hash) ? ins[:__docscribe_plugin_order] : nil
          order.nil? ? 0 : order
        end
      end

      # Warn about override conflicts in debug mode.
      # @private
      # @param [Object] winners_sorted sorted override winners at max priority
      # @param [Object] max_prio the maximum priority value
      # @param [Object] pos the source position of the conflict
      # @return [Object]
      def warn_override_conflict!(winners_sorted, max_prio, pos)
        return unless Docscribe::Plugin.debug?

        labels = winners_sorted.map { |_k, ins| plugin_insertion_label(ins) }.uniq
        return unless labels.size > 1

        line = plugin_insertion_line(winners_sorted.first[1])
        loc = +"pos=#{pos}"
        loc << " line=#{line}" if line
        warn "Docscribe: method_override conflict at #{loc} (priority=#{max_prio}): " \
             "#{labels.join(', ')} — using first by registration order."
      end

      # @private
      # @param [Hash] insertion
      # @raise [StandardError]
      # @return [Integer]
      def plugin_insertion_priority(insertion)
        return 0 unless insertion.is_a?(Hash)

        Integer(insertion[:__docscribe_priority] || 0)
      rescue StandardError
        0
      end

      # @private
      # @param [Hash] insertion
      # @raise [StandardError]
      # @return [String]
      def plugin_insertion_label(insertion)
        return 'unknown' unless insertion.is_a?(Hash)

        label = insertion[:__docscribe_plugin_class].to_s
        label.empty? ? 'unknown' : label
      rescue StandardError
        'unknown'
      end

      # @private
      # @param [Hash] insertion
      # @raise [StandardError]
      # @return [Integer, nil]
      def plugin_insertion_line(insertion)
        return nil unless insertion.is_a?(Hash)

        anchor_node = insertion[:anchor_node]
        expression = anchor_node&.loc&.expression
        expression&.line
      rescue StandardError
        nil
      end

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
      # @param [Docscribe::Config] config
      # @return [void]
      def apply_plugin_insertion!(rewriter:, buffer:, insertion:, strategy:, config:)
        anchor_node, doc = insertion.values_at(:anchor_node, :doc)
        return unless anchor_node && doc && !doc.empty?

        indent = SourceHelpers.line_indent(anchor_node)
        doc = normalize_plugin_doc(doc, indent, config: config, anchor_node: anchor_node)
        bol_range = SourceHelpers.line_start_range(buffer, anchor_node)
        insert_plugin_doc(rewriter, buffer, bol_range, doc, strategy)
      end

      # Insert plugin doc according to strategy, handling comment removal.
      # @private
      # @param [Object] rewriter the TreeRewriter accumulating source transformations
      # @param [Object] buffer the source buffer being rewritten
      # @param [Object] bol_range the beginning-of-line range for the anchor node
      # @param [Object] doc the normalized documentation string to insert
      # @param [Object] strategy :safe or :aggressive rewrite mode
      # @return [Object]
      def insert_plugin_doc(rewriter, buffer, bol_range, doc, strategy)
        case strategy
        when :aggressive
          range = any_comment_block_removal_range(buffer, bol_range.begin_pos)
          rewriter.remove(range) if range
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
        i = nearest_comment_line_index(src, lines, bol_pos)
        return nil unless i

        start_idx = comment_block_start_index(lines, i)

        removable_start_idx = skip_preserved_lines(lines, start_idx, i)
        return nil if removable_start_idx > i

        start_pos = removable_start_idx.positive? ? lines[0...removable_start_idx].join.length : 0
        Parser::Source::Range.new(buffer, start_pos, bol_pos)
      end

      # Find the nearest comment line index above a position.
      # @private
      # @param [Object] src the full source string of the buffer
      # @param [Object] lines array of source code lines
      # @param [Object] bol_pos character position of the beginning of the anchor line
      # @return [Object]
      def nearest_comment_line_index(src, lines, bol_pos)
        def_line_idx = src[0...bol_pos].count("\n")
        i = def_line_idx - 1
        i -= 1 while i >= 0 && lines[i].strip.empty?
        return nil unless i >= 0 && lines[i] =~ /^\s*#/

        i
      end

      # Walk upward through contiguous comment block to find the start.
      # @private
      # @param [Object] lines array of source code lines
      # @param [Object] i line index of the bottommost comment in the contiguous block
      # @param [Object] def_line_idx the index in lines of the method definition (anchor) line
      # @return [Object]
      def comment_block_start_index(lines, def_line_idx)
        start_idx = def_line_idx
        start_idx -= 1 while start_idx >= 0 && lines[start_idx] =~ /^\s*#/
        start_idx + 1
      end

      # Skip preserved directive-style lines at the top of the comment block.
      # @private
      # @param [Object] lines array of source code lines
      # @param [Object] start_idx index of the first line of the comment block
      # @param [Object] i current line index while walking upward through the block
      # @param [Object] def_line_idx the index in lines of the method definition (anchor) line
      # @return [Object]
      def skip_preserved_lines(lines, start_idx, def_line_idx)
        idx = start_idx
        idx += 1 while idx <= def_line_idx && SourceHelpers.preserved_comment_line?(lines[idx])
        idx
      end

      # Normalize a CollectorPlugin-provided doc string before insertion.
      #
      # Responsibilities:
      # - apply indentation based on the anchor node
      # - trim trailing whitespace-only lines
      # - (optionally) prepend the configured default message for `def/defs` anchors
      #   when the plugin output contains only tags (no prose)
      #
      # @private
      # @param doc [String] Raw doc string returned by a CollectorPlugin insertion (`:doc`)
      # @param indent [String] Indentation to apply to every doc line
      # @param config [Docscribe::Config] Effective Docscribe config for this run
      # @param anchor_node [Parser::AST::Node, nil] AST node used as insertion anchor
      # @return [String] Normalized doc string ready to be inserted
      def normalize_plugin_doc(doc, indent, config:, anchor_node:)
        doc = normalize_plugin_doc_indent(doc, indent)
        doc = trim_trailing_blank_lines(doc)

        if %i[def defs].include?(anchor_node&.type) && config.include_default_message?
          doc = prepend_default_message_if_no_prose(doc, anchor_node, indent, config)
        end

        doc
      end

      # Trim trailing blank lines from a doc string.
      # @private
      # @param [Object] doc the documentation string to trim
      # @return [Object]
      def trim_trailing_blank_lines(doc)
        lines = doc.lines
        lines.pop while lines.any? && lines.last.strip.empty?
        result = lines.join
        result.end_with?("\n") ? result : "#{result}\n"
      end

      # Prepend default message if the doc block has only tags.
      # @private
      # @param [Object] doc the plugin-generated documentation string
      # @param [Object] anchor_node the AST node used as the insertion anchor
      # @param [Object] indent whitespace indentation prefix derived from the anchor node
      # @param [Object] config the active Docscribe::Config
      # @return [Object]
      def prepend_default_message_if_no_prose(doc, anchor_node, indent, config)
        return doc if doc_has_prose?(doc)

        scope = anchor_node.type == :defs ? :class : :instance
        msg = config.default_message(scope, :public)
        "#{indent}# #{msg}\n#{indent}#\n" + doc
      end

      # Check if a doc block has any prose content.
      # @private
      # @param [Object] doc the documentation string to inspect
      # @return [Boolean]
      def doc_has_prose?(doc)
        doc.lines.any? do |l|
          s = l.strip
          next false if s.empty? || s == '#'
          next false if s.start_with?('# @')
          next false if s.start_with?('# +')

          true
        end
      end

      # Normalize indentation of a plugin-generated doc block.
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
      # @param [Hash] options kwargs with insertion, config, rewriter, buffer, strategy, changes, file, doc params
      # @return [void]
      def apply_method_insertion!(**options)
        insertion = options[:insertion]
        config = options[:config]
        return unless method_insertion_allowed?(insertion, config)

        anchor_bol_range, = method_bol_ranges(options[:buffer], insertion)
        params = build_method_insertion_params(insertion, config, options[:signature_provider],
                                               options[:core_rbs_provider], options[:method_override])
        doc = build_method_doc(insertion, **params)
        dispatch_method_insertion_by_strategy!(anchor_bol_range, options, params, doc)
      end

      # Dispatch method insertion to the aggressive or safe handler.
      # @private
      # @param [Object] anchor_bol_range the beginning-of-line range for the anchor node
      # @param [Object] options the full keyword options hash passed to apply_method_insertion!
      # @param [Object] params precomputed insertion parameters (types, overrides, config)
      # @param [Object] doc the generated documentation block string
      # @return [Object]
      def dispatch_method_insertion_by_strategy!(anchor_bol_range, options, params, doc)
        base = { anchor_bol_range: anchor_bol_range, insertion: options[:insertion],
                 rewriter: options[:rewriter], buffer: options[:buffer],
                 changes: options[:changes], file: options[:file] }
        case options[:strategy]
        when :aggressive then apply_method_insertion_aggressive!(**base, doc: doc)
        when :safe then apply_method_insertion_safe!(**base, strategy: options[:strategy], **params)
        end
      end

      # Validate and prepare for method insertion.
      #
      # @private
      # @param [Collector::Insertion] insertion
      # @param [Docscribe::Config] config
      # @return [Boolean] true if insertion should proceed
      def method_insertion_allowed?(insertion, config)
        name = SourceHelpers.node_name(insertion.node)
        config.process_method?(container: insertion.container, scope: insertion.scope,
                               visibility: insertion.visibility, name: name)
      end

      # Build all parameters needed for method insertion.
      #
      # @private
      # @param [Collector::Insertion] insertion
      # @param [Docscribe::Config] config
      # @param [Object, nil] signature_provider
      # @param [Object, nil] core_rbs_provider
      # @param [Hash, nil] method_override
      # @return [Hash]
      def build_method_insertion_params(insertion, config, signature_provider, core_rbs_provider, method_override)
        override = extract_method_override!(method_override)
        effective = build_effective_params(insertion, config: config, signature_provider: signature_provider,
                                                      core_rbs_provider: core_rbs_provider, override: override)
        { **effective, config: config, signature_provider: signature_provider,
                       core_rbs_provider: core_rbs_provider }
      end

      # Build effective parameters merging external signatures and overrides.
      #
      # @private
      # @param [Collector::Insertion] insertion
      # @param [Hash] options keyword options
      # @return [Hash{Symbol => Object}]
      def build_effective_params(insertion, **options)
        external_sig = resolve_external_signature(insertion, options[:signature_provider])
        param_types = resolve_param_types(insertion, external_sig, options[:config])
        override = options[:override]

        param_types = param_types.merge(override[:param_types]) if override[:param_types]&.any?

        { param_types: param_types, return_type_override: override[:return_type], override_tags: override[:tags] }
      end

      # Resolve external signature for an insertion.
      # @private
      # @param [Object] insertion the collected method insertion
      # @param [Object] signature_provider external RBS signature provider
      # @return [Object]
      def resolve_external_signature(insertion, signature_provider)
        signature_provider&.signature_for(
          container: insertion.container,
          scope: insertion.scope,
          name: SourceHelpers.node_name(insertion.node)
        )
      end

      # Resolve param types from signature or fall back to node parsing.
      # @private
      # @param [Object] insertion the collected method insertion
      # @param [Object] external_sig the resolved signature from the signature provider
      # @param [Object] config the active Docscribe::Config
      # @return [Object]
      def resolve_param_types(insertion, external_sig, config)
        external_sig&.param_types || DocBuilder.build_param_types_from_node(
          insertion.node, external_sig: external_sig, config: config
        )
      end

      # Apply method insertion in aggressive strategy mode.
      #
      # @private
      # @param [Hash] options keyword options
      # @return [void]
      def apply_method_insertion_aggressive!(**options)
        rewriter = options[:rewriter]
        buffer = options[:buffer]
        insertion = options[:insertion]
        doc = options[:doc]

        remove_method_comment_block(rewriter, buffer, insertion)
        return if doc.nil? || doc.empty?

        rewriter.insert_before(options[:anchor_bol_range], doc)
        add_change(changes: options[:changes], type: :insert_full_doc_block,
                   insertion: insertion, file: options[:file], message: 'missing docs')
      end

      # Remove the comment block above a method when present.
      # @private
      # @param [Object] rewriter the TreeRewriter accumulating source transformations
      # @param [Object] buffer the source buffer being rewritten
      # @param [Object] insertion the collected method insertion
      # @return [Object]
      def remove_method_comment_block(rewriter, buffer, insertion)
        range = method_comment_block_removal_range(buffer, insertion)
        rewriter.remove(range) if range
      end

      # Apply method insertion in safe strategy mode.
      #
      # @private
      # @param [Hash] options keyword options
      # @return [void]
      def apply_method_insertion_safe!(**options)
        info = method_doc_comment_info(options[:buffer], options[:insertion])

        if info
          apply_method_insertion_safe_with_info!(**options, info: info)
        else
          apply_method_insertion_safe_without_info!(**options)
        end
      end

      # Apply method insertion in safe mode when existing doc info is present.
      #
      # @private
      # @param [Hash] options keyword options
      # @return [void]
      def apply_method_insertion_safe_with_info!(**options)
        i = options[:info]
        dp = filter_doc_params(options)
        mr = build_missing_method_merge_result(options[:insertion], existing_lines: i[:doc_lines],
                                                                    strategy: options[:strategy], **dp)
        changed, n, ob = compute_doc_replacement(i, mr[:lines], strategy: options[:strategy], **dp)
        commit_safe_doc_outcome(options[:rewriter], options[:buffer], i, n,
                                old_block: ob, merge_result: mr,
                                existing_order_changed: changed,
                                insertion: options[:insertion], changes: options[:changes],
                                file: options[:file])
      end

      # Commit doc replacement and log changes for safe mode.
      # @private
      # @param [Object] rewriter the TreeRewriter accumulating source transformations
      # @param [Object] buffer the source buffer being rewritten
      # @param [Object] info hash containing existing doc comment block data
      # @param [Object] new_block the newly constructed replacement doc block string
      # @param [Hash] rest additional kwargs (old_block, merge_result, existing_order_changed, insertion, changes, file)
      # @return [Object]
      def commit_safe_doc_outcome(rewriter, buffer, info, new_block, **rest)
        handle_doc_replacement(rewriter, buffer, info, new_block,
                               insertion: rest[:insertion], changes: rest[:changes],
                               file: rest[:file],
                               existing_order_changed: rest[:existing_order_changed])
        log_method_doc_changes!(insertion: rest[:insertion], merge_result: rest[:merge_result],
                                new_block: new_block, old_block: rest[:old_block],
                                changes: rest[:changes], file: rest[:file])
      end

      # Filter doc params from options hash.
      # @private
      # @param [Object] options the full options hash to filter
      # @return [Object]
      def filter_doc_params(options)
        options.reject { |k, _| %i[rewriter buffer insertion anchor_bol_range info changes file strategy].include?(k) }
      end

      # Handle replacement when doc block content changed.
      # @private
      # @param [Object] rewriter the TreeRewriter accumulating source transformations
      # @param [Object] buffer the source buffer being rewritten
      # @param [Object] info hash containing existing doc comment block data (start_pos, end_pos, lines)
      # @param [Object] new_block the newly constructed replacement doc block string
      # @param [Object] existing_order_changed boolean indicating tag order was modified by sorting
      # @param [Object] insertion the collected method insertion
      # @param [Object] changes array of structured change records for reporting
      # @param [Object] file the source file path string
      # @param [Hash] log_opts additional keyword arguments for logging and recording changes
      # @return [Object]
      def handle_doc_replacement(rewriter, buffer, info, new_block, **log_opts)
        range = Parser::Source::Range.new(buffer, info[:start_pos], info[:end_pos])
        rewriter.replace(range, new_block)

        return unless log_opts[:existing_order_changed]

        add_change(changes: log_opts[:changes], type: :unsorted_tags,
                   insertion: log_opts[:insertion], file: log_opts[:file],
                   message: 'unsorted tags')
      end

      # Compute merged doc lines and determine if replacement is needed.
      #
      # @private
      # @param [Hash] info existing doc info
      # @param [Array<String>] missing_lines
      # @param [Hash] options keyword options
      # @return [Array] [existing_order_changed, new_block, old_block]
      def compute_doc_replacement(info, missing_lines, **options)
        dc = options[:config]
        sorted = Docscribe::InlineRewriter::DocBlock.merge(
          info[:doc_lines], missing_lines: [], sort_tags: dc.sort_tags?, tag_order: dc.tag_order
        )
        merged = Docscribe::InlineRewriter::DocBlock.merge(
          info[:doc_lines], missing_lines: missing_lines, sort_tags: dc.sort_tags?, tag_order: dc.tag_order
        )
        [sorted != info[:doc_lines], (info[:preserved_lines] + merged).join, info[:lines].join]
      end

      # Log changes for method doc updates.
      #
      # @private
      # @param [Collector::Insertion] insertion
      # @param [Hash] merge_result
      # @param [String] new_block
      # @param [String] old_block
      # @param [Array<Hash>] changes
      # @param [String] file
      # @param [Hash] rest additional keyword arguments forwarded to add_change
      # @return [Object]
      def log_method_doc_changes!(insertion:, merge_result:, **rest)
        reason_specs = merge_result[:reasons] || []
        type_mismatch_reasons = reason_specs.select { |r| %i[updated_param updated_return].include?(r[:type]) }

        return unless rest[:new_block] != rest[:old_block] || type_mismatch_reasons.any?

        reason_specs.each do |reason|
          add_change(changes: rest[:changes], type: reason[:type], insertion: insertion,
                     file: rest[:file], message: reason[:message], extra: reason[:extra] || {})
        end
      end

      # Apply method insertion in safe mode when no existing doc info is present.
      #
      # @private
      # @param [Hash] options keyword options
      # @return [void]
      def apply_method_insertion_safe_without_info!(**options)
        rewriter = options[:rewriter]
        insertion = options[:insertion]
        anchor_bol_range = options[:anchor_bol_range]
        doc = build_method_doc(insertion, **filter_method_doc_params(options))
        return if doc.nil? || doc.empty?

        rewriter.insert_before(anchor_bol_range, doc)
        add_change(changes: options[:changes], type: :insert_full_doc_block,
                   insertion: insertion, file: options[:file], message: 'missing docs')
      end

      # Filter options to keep only doc-building params for safe-without-info mode.
      # @private
      # @param [Object] options the full options hash to filter
      # @return [Object]
      def filter_method_doc_params(options)
        options.reject { |k, _| %i[rewriter buffer insertion anchor_bol_range changes file strategy].include?(k) }
      end

      # Append a structured change record.
      #
      # @private
      # @param [Hash] options kwargs for change record (type, file, line, method, message, insertion, changes, extra)
      # @return [void]
      def add_change(**options)
        changes = options[:changes]
        changes << {
          type: options[:type],
          file: options[:file],
          line: options[:line] || method_line_for(options[:insertion]),
          method: method_id_for(options[:insertion]),
          message: options[:message]
        }.merge(options[:extra] || {})
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
      # @param [Hash] options kwargs (insertion, config, rewriter, buffer, strategy, signature_provider, merge_inserts)
      # @return [void]
      def apply_attr_insertion!(**options)
        config = options[:config]
        return unless config.respond_to?(:emit_attributes?) && config.emit_attributes?
        return unless attribute_allowed?(config, options[:insertion])

        bol_range = SourceHelpers.line_start_range(options[:buffer], options[:insertion].node)
        params = attr_insertion_params(options[:insertion], config, options[:signature_provider], bol_range)
        dispatch_attr_strategy(params, options)
      end

      #
      # @private
      # @param [Object] insertion the collected attribute insertion
      # @param [Object] config the active Docscribe::Config
      # @param [Object] signature_provider external RBS signature provider
      # @param [Object] bol_range the beginning-of-line range for the attribute node
      # @return [Hash]
      def attr_insertion_params(insertion, config, signature_provider, bol_range)
        {
          insertion: insertion, config: config,
          signature_provider: signature_provider, bol_range: bol_range
        }
      end

      # Dispatch attr insertion to the aggressive or safe handler.
      # @private
      # @param [Object] params precomputed attribute insertion parameters
      # @param [Object] options the full keyword options hash
      # @return [Object]
      def dispatch_attr_strategy(params, options)
        case options[:strategy]
        when :aggressive then apply_attr_aggressive!(params, options[:rewriter])
        when :safe then apply_attr_safe!(params, options[:merge_inserts], options[:rewriter], options[:buffer])
        end
      end

      #
      # @private
      # @param [Object] params precomputed attribute insertion parameters
      # @param [Object] rewriter the TreeRewriter accumulating source transformations
      # @return [Object]
      def apply_attr_aggressive!(params, rewriter)
        if (range = SourceHelpers.comment_block_removal_range(params[:bol_range].begin_pos))
          rewriter.remove(range)
        end

        doc = build_attr_doc_for_node(params[:insertion], config: params[:config],
                                                          signature_provider: params[:signature_provider])
        return if doc.nil? || doc.empty?

        rewriter.insert_before(params[:bol_range], doc)
      end

      #
      # @private
      # @param [Object] params precomputed attribute insertion parameters
      # @param [Object] merge_inserts hash mapping end positions to arrays of doc additions
      # @param [Object] rewriter the TreeRewriter accumulating source transformations
      # @param [Object] buffer the source buffer being rewritten
      # @return [Object]
      def apply_attr_safe!(params, merge_inserts, rewriter, buffer)
        info = SourceHelpers.doc_comment_block_info(buffer, params[:bol_range].begin_pos)

        if info
          merge_attr_additions!(insertion: params[:insertion], info: info, merge_inserts: merge_inserts,
                                config: params[:config], signature_provider: params[:signature_provider])
          return
        end

        doc = build_attr_doc_for_node(params[:insertion], config: params[:config],
                                                          signature_provider: params[:signature_provider])
        return if doc.nil? || doc.empty?

        rewriter.insert_before(params[:bol_range], doc)
      end

      #
      # @private
      # @param [Object] insertion the collected attribute insertion
      # @param [Object] info hash containing existing doc comment block data
      # @param [Object] merge_inserts hash mapping end positions to arrays of doc additions
      # @param [Object] config the active Docscribe::Config
      # @param [Object] signature_provider external RBS signature provider
      # @return [Object]
      def merge_attr_additions!(insertion:, info:, merge_inserts:, config:, signature_provider:)
        additions = build_attr_merge_additions(ins: insertion, existing_lines: info[:lines],
                                               config: config, signature_provider: signature_provider)
        return unless additions && !additions.empty?

        merge_inserts[info[:end_pos]] << [insertion.node.loc.expression.begin_pos, additions]
      end

      #
      # @private
      # @param [Object] rewriter the TreeRewriter accumulating source transformations
      # @param [Object] buffer the source buffer being rewritten
      # @param [Object] merge_inserts hash mapping end positions to arrays of attribute doc additions
      # @return [Object]
      def apply_merge_inserts!(rewriter:, buffer:, merge_inserts:)
        merge_inserts.keys.sort.reverse_each do |end_pos|
          text = merge_text_for_pos(merge_inserts[end_pos])
          next if text.nil? || text.empty?

          range = Parser::Source::Range.new(buffer, end_pos, end_pos)
          rewriter.insert_before(range, text)
        end
      end

      #
      # @private
      # @param [Object] chunks array of [sort_key, doc_text] pairs for a given merge position
      # @return [Object, nil]
      def merge_text_for_pos(chunks)
        return nil if chunks.empty?

        chunks = chunks.sort_by { |(sort_key, _s)| sort_key }
        out_lines = [] #: Array[String]
        sep_re = /^\s*#\s*\r?\n$/

        chunks.each do |(_k, chunk)|
          next if chunk.nil? || chunk.empty?

          merge_chunk_into_out(chunk, out_lines, sep_re)
        end

        text = out_lines.join
        text.empty? ? nil : text
      end

      # Merge a single chunk into the output lines array.
      # @private
      # @param [Object] chunk the doc text string to merge
      # @param [Object] out_lines the accumulated output lines array
      # @param [Object] sep_re regex matching separator comment lines (# followed by newline)
      # @return [Object]
      def merge_chunk_into_out(chunk, out_lines, sep_re)
        lines = chunk.lines
        seps = extract_separators(lines, sep_re)
        sep = seps.first
        out_lines << sep if sep && (out_lines.empty? || !out_lines.last.match?(sep_re))
        out_lines.concat(lines)
      end

      # Extract leading separator lines from a chunk.
      # @private
      # @param [Object] lines array of lines from the chunk
      # @param [Object] sep_re regex matching separator comment lines
      # @return [Object]
      def extract_separators(lines, sep_re)
        seps = [] #: Array[String]
        seps << lines.shift while !lines.empty? && lines.first.match?(sep_re)
        seps
      end

      #
      # @private
      # @param [Object] ins the attribute insertion object
      # @param [Object] existing_lines array of existing doc comment lines
      # @param [Object] config the active Docscribe::Config
      # @param [Object] signature_provider external RBS signature provider
      # @raise [StandardError]
      # @return [Object]
      # @return [nil] if StandardError
      def build_attr_merge_additions(ins:, existing_lines:, config:, signature_provider:)
        missing = missing_attr_names(ins, existing_lines)
        return '' if missing.empty?

        indent = SourceHelpers.line_indent(ins.node)
        lines = [] #: Array[String]
        lines << "#{indent}#" if existing_lines.any? && existing_lines.last.strip != '#'
        lines.concat(build_attr_doc_lines(ins, indent: indent, config: config,
                                               signature_provider: signature_provider, names: missing))
        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      #
      # @private
      # @param [Object] ins the attribute insertion object
      # @param [Object] existing_lines array of existing doc comment lines
      # @return [Object]
      def missing_attr_names(ins, existing_lines)
        existing = existing_attr_names(existing_lines)
        ins.names.reject { |name_sym| existing[name_sym.to_s] }
      end

      #
      # @private
      # @param [Object] lines array of existing doc comment lines
      # @return [Object]
      def existing_attr_names(lines)
        names = {} #: Hash[String, bool]

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
          allowed_for_access?(config, ins, name_sym)
        end
      end

      #
      # @private
      # @param [Object] config the active Docscribe::Config
      # @param [Object] ins the attribute insertion object
      # @param [Object] name_sym the attribute name as a Symbol
      # @return [Object]
      def allowed_for_access?(config, ins, name_sym)
        ok = false

        if %i[r rw].include?(ins.access)
          ok ||= config.process_method?(container: ins.container, scope: ins.scope,
                                        visibility: ins.visibility, name: name_sym)
        end

        if %i[w rw].include?(ins.access)
          ok ||= config.process_method?(container: ins.container, scope: ins.scope,
                                        visibility: ins.visibility, name: :"#{name_sym}=")
        end

        ok
      end

      #
      # @private
      # @param [Object] ins the attribute insertion object
      # @param [Object] config the active Docscribe::Config
      # @param [Object] signature_provider external RBS signature provider
      # @raise [StandardError]
      # @return [Object]
      # @return [nil] if StandardError
      def build_attr_doc_for_node(ins, config:, signature_provider:)
        indent = SourceHelpers.line_indent(ins.node)
        lines = build_attr_doc_lines(ins, indent: indent, config: config, signature_provider: signature_provider)
        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      #
      # @private
      # @param [Object] ins the attribute insertion object
      # @param [Object] indent whitespace indentation prefix derived from the attribute node
      # @param [Object] config the active Docscribe::Config
      # @param [Object] signature_provider external RBS signature provider
      # @param [nil] names optional subset of attribute names to document (defaults to all names)
      # @return [Object]
      def build_attr_doc_lines(ins, indent:, config:, signature_provider:, names: nil)
        names ||= ins.names
        lines = [] #: Array[untyped]

        names.each_with_index do |name_sym, idx|
          lines.concat(build_single_attr_lines(ins, name_sym, indent: indent,
                                                              config: config, signature_provider: signature_provider,
                                                              idx: idx, total: names.length))
        end

        lines
      end

      # Build doc lines for a single attribute.
      # @private
      # @param [Object] ins the attribute insertion object
      # @param [Object] name_sym the attribute name as a Symbol
      # @param [Object] idx index of the current attribute in the names array
      # @param [Object] total total number of attributes to document
      # @param [Object] indent whitespace indentation prefix
      # @param [Object] config the active Docscribe::Config
      # @param [Object] signature_provider external RBS signature provider
      # @param [Hash] opts additional keyword arguments forwarded from build_attr_doc_lines
      # @return [Object]
      def build_single_attr_lines(ins, name_sym, indent:, **opts)
        cfg = opts[:config]
        attr_type = attribute_type(ins, name_sym, cfg, signature_provider: opts[:signature_provider])
        lines = ["#{indent}# @!attribute [#{ins.access}] #{name_sym}"]
        lines.concat(attr_visibility_lines(indent, cfg, ins))
        append_attr_return_tag(lines, indent, attr_type, ins.access)
        append_attr_param_tag(lines, indent, attr_type, ins.access, cfg)
        lines << "#{indent}#" if opts[:idx] < opts[:total] - 1
        lines
      end

      # Append @return tag for readable attribute.
      # @private
      # @param [Object] lines the doc lines array being built
      # @param [Object] indent whitespace indentation prefix
      # @param [Object] attr_type the resolved type string for the attribute
      # @param [Object] access the access level (:r, :w, or :rw)
      # @return [Object]
      def append_attr_return_tag(lines, indent, attr_type, access)
        lines << "#{indent}#   @return [#{attr_type}]" if %i[r rw].include?(access)
      end

      # Append @param tag for writable attribute.
      # @private
      # @param [Object] lines the doc lines array being built
      # @param [Object] indent whitespace indentation prefix
      # @param [Object] attr_type the resolved type string for the attribute
      # @param [Object] access the access level (:r, :w, or :rw)
      # @param [Object] cfg the active Docscribe::Config
      # @return [Object]
      def append_attr_param_tag(lines, indent, attr_type, access, cfg)
        return unless %i[w rw].include?(access)

        lines << format_attribute_param_tag(indent, 'value', attr_type, style: cfg.param_tag_style)
      end

      # Build visibility lines for an attribute.
      # @private
      # @param [Object] indent whitespace indentation prefix
      # @param [Object] config the active Docscribe::Config
      # @param [Object] ins the attribute insertion object
      # @return [Object]
      def attr_visibility_lines(indent, config, ins)
        return [] unless config.emit_visibility_tags?

        lines = [] #: Array[String]
        lines << "#{indent}# @private" if ins.visibility == :private
        lines << "#{indent}# @protected" if ins.visibility == :protected
        lines
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
      # @param [Object] signature_provider RBS signature provider
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
      # @param [Hash] options kwargs for DocBuilder.build (param_types, return_type_override, override_tags, config)
      # @return [String, nil] generated doc block or nil
      def build_method_doc(insertion, **options)
        DocBuilder.build(insertion, **options)
      end

      # Delegate to DocBuilder.build_missing_merge_result for generating missing doc lines only.
      #
      # @private
      # @param [Collector::Insertion] insertion the collected method insertion
      # @param [Array<String>] existing_lines existing doc-like lines
      # @param [Hash] options keyword arguments forwarded to DocBuilder.build_missing_merge_result
      # @return [Hash] result with `:lines` and `:reasons` keys
      def build_missing_method_merge_result(insertion, existing_lines:, **options)
        DocBuilder.build_missing_merge_result(insertion, existing_lines: existing_lines, **options)
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

      # Extract method override data from an insertion hash.
      #
      # @private
      # @param [Object] method_override the raw override data
      # @return [Hash{Symbol => Object}] normalized override hash
      def extract_method_override!(method_override)
        return {} unless method_override.is_a?(Hash)

        {
          return_type: method_override[:return_type],
          param_types: method_override[:param_types].is_a?(Hash) ? method_override[:param_types] : {},
          tags: normalize_override_tags(method_override[:tags])
        }
      end

      # Normalize override tags into Plugin::Tag instances.
      #
      # @private
      # @param [Array<Object>] tags raw tag values
      # @return [Array<Docscribe::Plugin::Tag>]
      def normalize_override_tags(tags)
        Array(tags).filter_map do |tag|
          case tag
          when Docscribe::Plugin::Tag then tag
          when Hash
            Docscribe::Plugin::Tag.new(**tag.transform_keys(&:to_sym))
          end
        end
      end
    end
  end
end
