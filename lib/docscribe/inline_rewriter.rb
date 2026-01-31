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
  # Rewrites Ruby source to insert YARD-style doc comments above method definitions.
  #
  # This is the “top-level” API most callers use:
  #
  # - CLI mode uses it to process files and print `.` / `F` / `C`.
  # - Library users can call {Docscribe::InlineRewriter.insert_comments}.
  #
  # Design goals:
  # - Preserve original formatting (no pretty-printing / reformatting).
  # - Only insert/remove comment blocks using {Parser::Source::TreeRewriter}.
  # - Respect Ruby visibility semantics using the AST walker in {Collector}.
  module InlineRewriter
    class << self
      # Insert documentation comments into Ruby source.
      #
      # Behavior:
      # - Parses Ruby source into a parser-gem compatible AST via {Docscribe::Parsing}.
      #   (On Ruby 3.4+ Docscribe uses Prism translation under the hood.)
      # - Walks AST and records candidate `def`/`defs` nodes with context
      #   (container/class/module name, instance vs class scope, and visibility).
      # - Inserts a generated doc block immediately above each candidate method.
      #
      # Skipping vs refresh:
      # - If `rewrite` is false (default), Docscribe skips methods that already have a comment line
      #   immediately above them (it does not merge into existing docs).
      # - If `rewrite` is true (CLI `--refresh`), Docscribe removes the contiguous comment block
      #   above the method and inserts a fresh generated block.
      #
      # @param code [String] Ruby source code
      # @param rewrite [Boolean] when true, regenerate docs even if a comment block exists above the method
      # @param config [Docscribe::Config, nil] configuration (defaults to {Docscribe::Config.load})
      # @return [String] rewritten Ruby source
      def insert_comments(code, rewrite: false, config: nil)
        buffer = Parser::Source::Buffer.new('(inline)', source: code)
        ast = Docscribe::Parsing.parse_buffer(buffer)

        # If parsing fails or returns nil, do nothing and return original source.
        return code unless ast

        config ||= Docscribe::Config.load

        collector = Docscribe::InlineRewriter::Collector.new(buffer)
        collector.process(ast)

        rewriter = Parser::Source::TreeRewriter.new(buffer)

        apply_insertions!(
          rewriter: rewriter,
          buffer: buffer,
          insertions: collector.insertions,
          config: config,
          rewrite: rewrite
        )

        rewriter.process
      end

      private

      # Apply all computed insertions to the rewriter.
      #
      # We process insertions bottom-up (reverse sorted by begin_pos) so that earlier edits do not
      # shift offsets for later edits.
      #
      # @param rewriter [Parser::Source::TreeRewriter]
      # @param buffer [Parser::Source::Buffer]
      # @param insertions [Array<Docscribe::InlineRewriter::Collector::Insertion>]
      # @param config [Docscribe::Config]
      # @param rewrite [Boolean]
      # @return [void]
      def apply_insertions!(rewriter:, buffer:, insertions:, config:, rewrite:)
        insertions
          .sort_by { |ins| ins.node.loc.expression.begin_pos }
          .reverse_each do |ins|
          name = SourceHelpers.node_name(ins.node)

          # Filtering by method-id (container + #/. + name), scopes, and visibilities.
          next unless config.process_method?(
            container: ins.container,
            scope: ins.scope,
            visibility: ins.visibility,
            name: name
          )

          bol_range = SourceHelpers.line_start_range(buffer, ins.node)

          if rewrite
            # Refresh mode: remove the comment block directly above the def, then re-insert.
            if (range = SourceHelpers.comment_block_removal_range(buffer, bol_range.begin_pos))
              rewriter.remove(range)
            end
          elsif SourceHelpers.already_has_doc_immediately_above?(buffer, bol_range.begin_pos)
            # Normal mode: do not touch if there is already a comment immediately above.
            next
          end

          doc = DocBuilder.build(ins, config: config)
          next if doc.nil? || doc.empty?

          rewriter.insert_before(bol_range, doc)
        end
      end
    end
  end
end
