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
  class ParseError < StandardError; end

  # Rewrites Ruby source to insert YARD-style documentation comments.
  #
  # Strategies:
  # - :safe       => insert missing docs, merge existing doc-like blocks, normalize sortable tags
  # - :aggressive => replace existing doc blocks with regenerated docs
  module InlineRewriter
    class << self
      # Insert documentation comments into Ruby source.
      #
      # @param code [String]
      # @param strategy [Symbol] :safe or :aggressive
      # @param config [Docscribe::Config, nil]
      # @param file [String]
      # @raise [Docscribe::ParseError]
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

      # Rewrite source and return both output and structured change reasons.
      #
      # @param code [String]
      # @param strategy [Symbol] :safe or :aggressive
      # @param config [Docscribe::Config, nil]
      # @param file [String]
      # @raise [Docscribe::ParseError]
      # @return [Hash]
      def rewrite_with_report(code, strategy: nil, rewrite: nil, merge: nil, config: nil, file: '(inline)')
        strategy = normalize_strategy(strategy: strategy, rewrite: rewrite, merge: merge)
        validate_strategy!(strategy)

        buffer = Parser::Source::Buffer.new(file.to_s, source: code)
        ast = Docscribe::Parsing.parse_buffer(buffer)
        raise Docscribe::ParseError, "Failed to parse #{file}" unless ast

        config ||= Docscribe::Config.load

        collector = Docscribe::InlineRewriter::Collector.new(buffer)
        collector.process(ast)

        method_insertions = collector.insertions
        attr_insertions = collector.respond_to?(:attr_insertions) ? collector.attr_insertions : []

        all = method_insertions.map { |i| [:method, i] } + attr_insertions.map { |i| [:attr, i] }

        rewriter = Parser::Source::TreeRewriter.new(buffer)
        merge_inserts = Hash.new { |h, k| h[k] = [] }
        changes = []

        all.sort_by { |(_kind, ins)| ins.node.loc.expression.begin_pos }
           .reverse_each do |kind, ins|
          case kind
          when :method
            apply_method_insertion!(
              rewriter: rewriter,
              buffer: buffer,
              insertion: ins,
              config: config,
              strategy: strategy,
              merge_inserts: merge_inserts,
              changes: changes,
              file: file.to_s
            )
          when :attr
            apply_attr_insertion!(
              rewriter: rewriter,
              buffer: buffer,
              insertion: ins,
              config: config,
              strategy: strategy,
              merge_inserts: merge_inserts
            )
          end
        end

        apply_merge_inserts!(rewriter: rewriter, buffer: buffer, merge_inserts: merge_inserts)

        {
          output: rewriter.process,
          changes: changes
        }
      end

      private

      def normalize_strategy(strategy:, rewrite:, merge:)
        return strategy if strategy

        return :aggressive if rewrite
        return :safe if merge

        :safe
      end

      def validate_strategy!(strategy)
        return if %i[safe aggressive].include?(strategy)

        raise ArgumentError, "Unknown strategy: #{strategy.inspect}"
      end

      # Apply one method insertion.
      #
      # :safe
      # - merge into existing doc-like block if present
      # - otherwise insert a full doc block non-destructively
      #
      # :aggressive
      # - replace existing doc block if present
      # - regenerate docs
      #
      # @param rewriter [Parser::Source::TreeRewriter]
      # @param buffer [Parser::Source::Buffer]
      # @param insertion [Docscribe::InlineRewriter::Collector::Insertion]
      # @param config [Docscribe::Config]
      # @param strategy [Symbol]
      # @param merge_inserts [Hash]
      # @param changes [Array<Hash>]
      # @param file [String]
      # @return [void]
      def apply_method_insertion!(rewriter:, buffer:, insertion:, config:, strategy:, merge_inserts:, changes:, file:)
        name = SourceHelpers.node_name(insertion.node)

        return unless config.process_method?(
          container: insertion.container,
          scope: insertion.scope,
          visibility: insertion.visibility,
          name: name
        )

        bol_range = SourceHelpers.line_start_range(buffer, insertion.node)

        case strategy
        when :aggressive
          if (range = SourceHelpers.comment_block_removal_range(buffer, bol_range.begin_pos))
            rewriter.remove(range)
          end

          doc = DocBuilder.build(insertion, config: config)
          return if doc.nil? || doc.empty?

          rewriter.insert_before(bol_range, doc)
          add_change(
            changes,
            type: :insert_full_doc_block,
            insertion: insertion,
            file: file,
            message: 'missing docs'
          )

        when :safe
          info = SourceHelpers.doc_comment_block_info(buffer, bol_range.begin_pos)

          if info
            merge_result = DocBuilder.build_missing_merge_result(
              insertion,
              existing_lines: info[:doc_lines],
              config: config
            )

            missing_lines = merge_result[:lines]
            reason_specs = merge_result[:reasons]

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

          doc = DocBuilder.build(insertion, config: config)
          return if doc.nil? || doc.empty?

          rewriter.insert_before(bol_range, doc)
          add_change(
            changes,
            type: :insert_full_doc_block,
            insertion: insertion,
            file: file,
            message: 'missing docs'
          )
        end
      end

      def add_change(changes, type:, insertion:, file:, message:, line: nil, extra: {})
        changes << {
          type: type,
          file: file,
          line: line || insertion.node.loc.expression.line,
          method: method_id_for(insertion),
          message: message
        }.merge(extra)
      end

      def method_id_for(insertion)
        name = SourceHelpers.node_name(insertion.node)
        "#{insertion.container}#{insertion.scope == :instance ? '#' : '.'}#{name}"
      end

      # Apply one attribute insertion.
      #
      # @param rewriter [Parser::Source::TreeRewriter]
      # @param buffer [Parser::Source::Buffer]
      # @param insertion [Docscribe::InlineRewriter::Collector::AttrInsertion]
      # @param config [Docscribe::Config]
      # @param strategy [Symbol]
      # @param merge_inserts [Hash]
      # @return [void]
      def apply_attr_insertion!(rewriter:, buffer:, insertion:, config:, strategy:, merge_inserts:)
        return unless config.respond_to?(:emit_attributes?) && config.emit_attributes?
        return unless attribute_allowed?(config, insertion)

        bol_range = SourceHelpers.line_start_range(buffer, insertion.node)

        case strategy
        when :aggressive
          if (range = SourceHelpers.comment_block_removal_range(buffer, bol_range.begin_pos))
            rewriter.remove(range)
          end

          doc = build_attr_doc_for_node(insertion, config: config)
          return if doc.nil? || doc.empty?

          rewriter.insert_before(bol_range, doc)

        when :safe
          info = SourceHelpers.doc_comment_block_info(buffer, bol_range.begin_pos)

          if info
            additions = build_attr_merge_additions(insertion, existing_lines: info[:lines], config: config)

            if additions && !additions.empty?
              merge_inserts[info[:end_pos]] << [insertion.node.loc.expression.begin_pos, additions]
            end
            return
          end

          doc = build_attr_doc_for_node(insertion, config: config)
          return if doc.nil? || doc.empty?

          rewriter.insert_before(bol_range, doc)
        end
      end

      # Apply aggregated merge inserts (one insert per end_pos).
      #
      # @param rewriter [Parser::Source::TreeRewriter]
      # @param buffer [Parser::Source::Buffer]
      # @param merge_inserts [Hash{Integer=>Array<(Integer,String)>}]
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

      def build_attr_merge_additions(ins, existing_lines:, config:)
        indent = SourceHelpers.line_indent(ins.node)
        existing = existing_attr_names(existing_lines)

        missing = ins.names.reject { |name_sym| existing[name_sym.to_s] }
        return '' if missing.empty?

        lines = []

        lines << "#{indent}#" if existing_lines.any? && existing_lines.last.strip != '#'

        missing.each_with_index do |name_sym, idx|
          attr_name = name_sym.to_s
          mode = ins.access.to_s
          attr_type = attribute_type(ins, name_sym, config)

          lines << "#{indent}# @!attribute [#{mode}] #{attr_name}"

          if config.emit_visibility_tags?
            lines << "#{indent}# @private" if ins.visibility == :private
            lines << "#{indent}# @protected" if ins.visibility == :protected
          end

          lines << "#{indent}#   @return [#{attr_type}]" if %i[r rw].include?(ins.access)
          lines << "#{indent}#   @param value [#{attr_type}]" if %i[w rw].include?(ins.access)

          lines << "#{indent}#" if idx < missing.length - 1
        end

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      def existing_attr_names(lines)
        names = {}
        Array(lines).each do |line|
          if (m = line.match(/^\s*#\s*@!attribute\b.*\]\s+(\S+)/))
            names[m[1]] = true
          end
        end
        names
      end

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

      def build_attr_doc_for_node(ins, config:)
        indent = SourceHelpers.line_indent(ins.node)
        lines = []

        ins.names.each_with_index do |name_sym, idx|
          attr_name = name_sym.to_s
          mode = ins.access.to_s

          attr_type = attribute_type(ins, name_sym, config)

          lines << "#{indent}# @!attribute [#{mode}] #{attr_name}"

          if config.emit_visibility_tags?
            lines << "#{indent}# @private" if ins.visibility == :private
            lines << "#{indent}# @protected" if ins.visibility == :protected
          end

          lines << "#{indent}#   @return [#{attr_type}]" if %i[r rw].include?(ins.access)
          lines << "#{indent}#   @param value [#{attr_type}]" if %i[w rw].include?(ins.access)

          lines << "#{indent}#" if idx < ins.names.length - 1
        end

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      def attribute_type(ins, name_sym, config)
        ty = config.fallback_type

        provider = config.rbs_provider
        return ty unless provider

        reader_sig = provider.signature_for(container: ins.container, scope: ins.scope, name: name_sym)
        reader_sig&.return_type || ty
      rescue StandardError
        config.fallback_type
      end
    end
  end
end
