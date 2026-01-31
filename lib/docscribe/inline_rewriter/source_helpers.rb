# frozen_string_literal: true

require 'parser/source/range'

module Docscribe
  module InlineRewriter
    # Source-level helpers for locating insertion points and detecting/removing comment blocks.
    module SourceHelpers
      module_function

      # Return the method name for a def/defs node.
      #
      # @param node [Parser::AST::Node]
      # @return [Symbol, nil]
      def node_name(node)
        case node.type
        when :def then node.children[0]
        when :defs then node.children[1]
        end
      end

      # Return a Range representing the start-of-line where a node begins.
      #
      # Used as the insertion point for doc blocks.
      #
      # @param buffer [Parser::Source::Buffer]
      # @param node [Parser::AST::Node]
      # @return [Parser::Source::Range]
      def line_start_range(buffer, node)
        start_pos = node.loc.expression.begin_pos
        src = buffer.source
        bol = src.rindex("\n", start_pos - 1) || -1
        Parser::Source::Range.new(buffer, bol + 1, bol + 1)
      end

      # Compute the source range to remove when refreshing docs.
      #
      # This removes the contiguous comment block immediately above the method definition,
      # plus any blank lines separating it from the `def` line.
      #
      # @param buffer [Parser::Source::Buffer]
      # @param def_bol_pos [Integer] absolute offset of the beginning-of-line of the `def`
      # @return [Parser::Source::Range, nil]
      def comment_block_removal_range(buffer, def_bol_pos)
        src = buffer.source
        lines = src.lines
        def_line_idx = src[0...def_bol_pos].count("\n")
        i = def_line_idx - 1

        # Skip blank lines directly above def
        i -= 1 while i >= 0 && lines[i].strip.empty?

        # Nearest non-blank line must be a comment to remove anything
        return nil unless i >= 0 && lines[i] =~ /^\s*#/

        # Walk up to find start of contiguous comment block
        start_idx = i
        start_idx -= 1 while start_idx >= 0 && lines[start_idx] =~ /^\s*#/
        start_idx += 1

        start_pos = start_idx.positive? ? lines[0...start_idx].join.length : 0
        Parser::Source::Range.new(buffer, start_pos, def_bol_pos)
      end

      # Check whether there is a comment (doc block or any comment line) immediately above the insertion point.
      #
      # This is the “non-refresh” skip mechanism: if a comment is already there, we assume the user has docs.
      #
      # @param buffer [Parser::Source::Buffer]
      # @param insert_pos [Integer] absolute offset where docs would be inserted (usually BOL of def)
      # @return [Boolean]
      def already_has_doc_immediately_above?(buffer, insert_pos)
        src = buffer.source
        lines = src.lines
        current_line_index = src[0...insert_pos].count("\n")
        i = current_line_index - 1
        i -= 1 while i >= 0 && lines[i].strip.empty?
        return false if i.negative?

        !!(lines[i] =~ /^\s*#/)
      end
    end
  end
end
