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
  # Inserts YARD-style comment blocks above method definitions (`def` and `defs`) in Ruby source.
  #
  # This module:
  # - parses Ruby into a parser-compatible AST (Parser gem AST; Prism translation on Ruby 3.4+ via Docscribe::Parsing)
  # - collects candidate method nodes and their context (container, scope, visibility)
  # - decides whether to skip, insert, or refresh existing doc blocks
  # - uses Parser::Source::TreeRewriter so the original formatting is preserved
  module InlineRewriter
    class << self
      # Insert documentation comments into Ruby source.
      #
      # Modes:
      # - default (rewrite: false): insert docs only when there is no comment block immediately above the method
      # - refresh  (rewrite: true): remove the contiguous comment block immediately above the method and insert a fresh one
      #
      # This method does not reformat Ruby code. It only inserts/removes comment blocks.
      #
      # @param code [String] Ruby source code
      # @param rewrite [Boolean] when true, regenerate docs even if a comment block exists above the method
      # @param config [Docscribe::Config, nil] config instance; defaults to Docscribe::Config.load
      # @return [String] rewritten source
      def insert_comments(code, rewrite: false, config: nil)
        buffer = Parser::Source::Buffer.new('(inline)', source: code)
        ast = Docscribe::Parsing.parse_buffer(buffer)
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

      # Apply doc insertions (and optional refresh removals) to a TreeRewriter.
      #
      # Insertions are processed bottom-up (reverse sorted by begin_pos) so offsets remain valid.
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

          next unless config.process_method?(
            container: ins.container,
            scope: ins.scope,
            visibility: ins.visibility,
            name: name
          )

          bol_range = SourceHelpers.line_start_range(buffer, ins.node)

          if rewrite
            if (range = SourceHelpers.comment_block_removal_range(buffer, bol_range.begin_pos))
              rewriter.remove(range)
            end
          elsif SourceHelpers.already_has_doc_immediately_above?(buffer, bol_range.begin_pos)
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
