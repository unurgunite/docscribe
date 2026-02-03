# frozen_string_literal: true

require 'ast'
require 'parser/deprecation'
require 'parser/source/buffer'
require 'parser/source/tree_rewriter'

require 'docscribe/config'
require 'docscribe/parsing'

require 'docscribe/inline_rewriter/source_helpers'
require 'docscribe/inline_rewriter/doc_builder'
require 'docscribe/inline_rewriter/collector'

module Docscribe
  # Rewrites Ruby source to insert YARD-style documentation comments.
  #
  # Docscribe uses Parser::Source::TreeRewriter so that the original formatting is preserved
  # (no pretty-printing). Only comment blocks are inserted/removed.
  #
  # Supported targets:
  # - method definitions (`def`, `defs`)
  # - attribute macros (`attr_reader`, `attr_writer`, `attr_accessor`) when enabled via config
  module InlineRewriter
    class << self
      # Insert documentation comments into Ruby source.
      #
      # Behavior:
      # - Parses Ruby source into a parser-gem compatible AST via {Docscribe::Parsing}
      #   (Prism translation is used automatically on Ruby 3.4+ unless overridden).
      # - Walks the AST via {Docscribe::InlineRewriter::Collector} to collect:
      #   - method insertions (def/defs)
      #   - attribute insertions (attr_*) when supported by collector
      # - Applies insertions bottom-up (reverse by source location) so offsets remain stable.
      #
      # Skipping vs refresh:
      # - rewrite: false (default): skip targets that already have a comment immediately above them
      # - rewrite: true  (CLI `--refresh`): remove the contiguous comment block above the target and re-insert
      #
      # @param code [String] Ruby source code
      # @param rewrite [Boolean] whether to regenerate docs even if a comment block exists above the target
      # @param config [Docscribe::Config, nil] configuration (defaults to {Docscribe::Config.load})
      # @return [String] rewritten Ruby source
      def insert_comments(code, rewrite: false, config: nil)
        buffer = Parser::Source::Buffer.new('(inline)', source: code)
        ast = Docscribe::Parsing.parse_buffer(buffer)
        return code unless ast

        config ||= Docscribe::Config.load

        collector = Docscribe::InlineRewriter::Collector.new(buffer)
        collector.process(ast)

        method_insertions = collector.insertions
        attr_insertions = collector.respond_to?(:attr_insertions) ? collector.attr_insertions : []

        # Combine insertions so methods and attrs are processed together in correct source order.
        all = method_insertions.map { |i| [:method, i] } + attr_insertions.map { |i| [:attr, i] }

        rewriter = Parser::Source::TreeRewriter.new(buffer)

        all.sort_by { |(_kind, ins)| ins.node.loc.expression.begin_pos }
           .reverse_each do |kind, ins|
          case kind
          when :method
            apply_method_insertion!(
              rewriter: rewriter,
              buffer: buffer,
              insertion: ins,
              config: config,
              rewrite: rewrite
            )
          when :attr
            apply_attr_insertion!(
              rewriter: rewriter,
              buffer: buffer,
              insertion: ins,
              config: config,
              rewrite: rewrite
            )
          end
        end

        rewriter.process
      end

      private

      # Apply one method insertion (def/defs).
      #
      # @param rewriter [Parser::Source::TreeRewriter]
      # @param buffer [Parser::Source::Buffer]
      # @param insertion [Docscribe::InlineRewriter::Collector::Insertion]
      # @param config [Docscribe::Config]
      # @param rewrite [Boolean]
      # @return [void]
      def apply_method_insertion!(rewriter:, buffer:, insertion:, config:, rewrite:)
        name = SourceHelpers.node_name(insertion.node)

        return unless config.process_method?(
          container: insertion.container,
          scope: insertion.scope,
          visibility: insertion.visibility,
          name: name
        )

        bol_range = SourceHelpers.line_start_range(buffer, insertion.node)

        if rewrite
          if (range = SourceHelpers.comment_block_removal_range(buffer, bol_range.begin_pos))
            rewriter.remove(range)
          end
        elsif SourceHelpers.already_has_doc_immediately_above?(buffer, bol_range.begin_pos)
          return
        end

        doc = DocBuilder.build(insertion, config: config)
        return if doc.nil? || doc.empty?

        rewriter.insert_before(bol_range, doc)
      end

      # Apply one attribute insertion (attr_reader/attr_writer/attr_accessor).
      #
      # This is gated by config.emit_attributes?.
      #
      # @param rewriter [Parser::Source::TreeRewriter]
      # @param buffer [Parser::Source::Buffer]
      # @param insertion [Docscribe::InlineRewriter::Collector::AttrInsertion]
      # @param config [Docscribe::Config]
      # @param rewrite [Boolean]
      # @return [void]
      def apply_attr_insertion!(rewriter:, buffer:, insertion:, config:, rewrite:)
        return unless config.respond_to?(:emit_attributes?) && config.emit_attributes?

        # Optionally respect method filters: only emit if at least one implied method is allowed.
        return unless attribute_allowed?(config, insertion)

        bol_range = SourceHelpers.line_start_range(buffer, insertion.node)

        if rewrite
          if (range = SourceHelpers.comment_block_removal_range(buffer, bol_range.begin_pos))
            rewriter.remove(range)
          end
        elsif SourceHelpers.already_has_doc_immediately_above?(buffer, bol_range.begin_pos)
          return
        end

        doc = build_attr_doc_for_node(insertion, config: config)
        return if doc.nil? || doc.empty?

        rewriter.insert_before(bol_range, doc)
      end

      # Decide whether an attribute macro should be documented, using method filters.
      #
      # For each attribute name, we translate it into implied method names:
      # - reader: `name`
      # - writer: `name=`
      #
      # If at least one implied method is allowed by config.process_method?, we generate docs.
      #
      # @param config [Docscribe::Config]
      # @param ins [Docscribe::InlineRewriter::Collector::AttrInsertion]
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

      # Build YARD `@!attribute` documentation for an attr_* insertion.
      #
      # Output format (example):
      #
      #   # @!attribute [r] name
      #   #   @return [String]
      #   attr_reader :name
      #
      # For writers/accessors we also emit:
      #
      #   #   @param value [String]
      #
      # Typing:
      # - Prefer RBS return type of the reader method when available.
      # - Otherwise use config.fallback_type.
      #
      # @param ins [Docscribe::InlineRewriter::Collector::AttrInsertion]
      # @param config [Docscribe::Config]
      # @return [String, nil]
      def build_attr_doc_for_node(ins, config:)
        indent = SourceHelpers.line_indent(ins.node)
        lines = []

        ins.names.each_with_index do |name_sym, idx|
          attr_name = name_sym.to_s
          mode = ins.access.to_s # "r", "w", "rw"

          attr_type = attribute_type(ins, name_sym, config)

          lines << "#{indent}# @!attribute [#{mode}] #{attr_name}"

          if config.emit_visibility_tags?
            lines << "#{indent}# @private" if ins.visibility == :private
            lines << "#{indent}# @protected" if ins.visibility == :protected
          end

          lines << "#{indent}#   @return [#{attr_type}]" if %i[r rw].include?(ins.access)
          lines << "#{indent}#   @param value [#{attr_type}]" if %i[w rw].include?(ins.access)

          # Separate multiple attrs in one macro call by a blank comment line
          lines << "#{indent}#" if idx < ins.names.length - 1
        end

        lines.map { |l| "#{l}\n" }.join
      rescue StandardError
        nil
      end

      # Determine an attribute type for a given attribute name.
      #
      # We use the reader signature when possible (it is the most natural source of truth),
      # and fall back to config.fallback_type otherwise.
      #
      # @param ins [Docscribe::InlineRewriter::Collector::AttrInsertion]
      # @param name_sym [Symbol]
      # @param config [Docscribe::Config]
      # @return [String]
      def attribute_type(ins, name_sym, config)
        ty = config.fallback_type

        provider = config.rbs_provider
        return ty unless provider

        # Use reader signature if present
        reader_sig = provider.signature_for(container: ins.container, scope: ins.scope, name: name_sym)
        reader_sig&.return_type || ty
      rescue StandardError
        config.fallback_type
      end
    end
  end
end
