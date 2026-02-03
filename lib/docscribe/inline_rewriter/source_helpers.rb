# frozen_string_literal: true

require 'parser/source/range'

module Docscribe
  module InlineRewriter
    # Source-level helpers: ranges, insertion positions, and comment-block detection.
    #
    # These helpers operate on:
    # - {Parser::Source::Buffer} (the full source)
    # - {Parser::AST::Node} locations (`node.loc.expression.begin_pos`, etc.)
    #
    # They intentionally do not parse Ruby semantics; they just handle raw text/ranges.
    module SourceHelpers
      module_function

      # Extract the Ruby method name from a `def` or `defs` node.
      #
      # @param node [Parser::AST::Node] a `:def` or `:defs` node
      # @return [Symbol, nil] method name symbol, or nil if node type is not supported
      def node_name(node)
        case node.type
        when :def then node.children[0]
        when :defs then node.children[1]
        end
      end

      # Compute the beginning-of-line range for the line containing the method definition.
      #
      # Docscribe uses this as the insertion point so docs appear flush above the `def`.
      #
      # @param buffer [Parser::Source::Buffer]
      # @param node [Parser::AST::Node]
      # @return [Parser::Source::Range] a zero-width range at the BOL
      def line_start_range(buffer, node)
        start_pos = node.loc.expression.begin_pos
        src = buffer.source
        bol = src.rindex("\n", start_pos - 1) || -1
        Parser::Source::Range.new(buffer, bol + 1, bol + 1)
      end

      # Return info about the contiguous doc-like comment block above a def line.
      #
      # Returns nil if:
      # - there is no contiguous comment block above the def, OR
      # - the block does not look like documentation (no header/tag markers)
      #
      # Result hash:
      # - :lines   => comment lines in the block (including preserved directives)
      # - :end_pos => absolute offset where the comment block ends (start of next line)
      #
      # @param buffer [Parser::Source::Buffer]
      # @param def_bol_pos [Integer]
      # @return [Hash, nil]
      def doc_comment_block_info(buffer, def_bol_pos)
        src = buffer.source
        lines = src.lines
        def_line_idx = src[0...def_bol_pos].count("\n")
        i = def_line_idx - 1

        # Skip blank lines directly above def
        i -= 1 while i >= 0 && lines[i].strip.empty?

        # Nearest non-blank line must be a comment
        return nil unless i >= 0 && lines[i] =~ /^\s*#/

        # Walk upward to include the entire contiguous comment block
        start_idx = i
        start_idx -= 1 while start_idx >= 0 && lines[start_idx] =~ /^\s*#/
        start_idx += 1

        # Preserve leading directive-style comments
        removable_start_idx = start_idx
        removable_start_idx += 1 while removable_start_idx <= i && preserved_comment_line?(lines[removable_start_idx])

        return nil if removable_start_idx > i

        remaining = lines[removable_start_idx..i]
        return nil unless remaining.any? { |line| doc_marker_line?(line) }

        # end_pos = start of line after i
        end_pos = lines[0..i].join.length

        {
          lines: lines[start_idx..i],
          end_pos: end_pos
        }
      end

      # Compute the range to remove when refreshing docs (`--refresh` / rewrite: true).
      #
      # The algorithm:
      # - Identify the line index of the method definition (based on `def_bol_pos`)
      # - Walk upward skipping blank lines
      # - If the first non-blank line is not a comment (`#`), do nothing
      # - Otherwise walk upward to include the entire contiguous comment block
      #
      # @param buffer [Parser::Source::Buffer]
      # @param def_bol_pos [Integer] absolute offset of the beginning of the `def` line
      # @return [Parser::Source::Range, nil] range to remove, or nil if nothing to remove
      def comment_block_removal_range(buffer, def_bol_pos)
        src = buffer.source
        lines = src.lines
        def_line_idx = src[0...def_bol_pos].count("\n")
        i = def_line_idx - 1

        # Skip blank lines directly above def
        i -= 1 while i >= 0 && lines[i].strip.empty?

        # Nearest non-blank line must be a comment to remove anything
        return nil unless i >= 0 && lines[i] =~ /^\s*#/

        # Walk upward to include the entire contiguous comment block
        start_idx = i
        start_idx -= 1 while start_idx >= 0 && lines[start_idx] =~ /^\s*#/
        start_idx += 1

        # Preserve leading directive-style comments (currently: rubocop directives)
        removable_start_idx = start_idx
        removable_start_idx += 1 while removable_start_idx <= i && preserved_comment_line?(lines[removable_start_idx])

        # If the whole block is preserved directives, there is nothing to remove
        return nil if removable_start_idx > i

        # SAFETY: only remove if the remaining block looks like documentation
        remaining = lines[removable_start_idx..i]
        return nil unless remaining.any? { |line| doc_marker_line?(line) }

        start_pos = removable_start_idx.positive? ? lines[0...removable_start_idx].join.length : 0
        Parser::Source::Range.new(buffer, start_pos, def_bol_pos)
      end

      def preserved_comment_line?(line)
        # RuboCop directives
        return true if line =~ /^\s*#\s*rubocop:(disable|enable|todo)\b/

        # Ruby magic comments
        return true if line =~ /^\s*#\s*(?:frozen_string_literal|warn_indent)\s*:\s*(?:true|false)\b/i
        return true if line =~ /^\s*#.*\b(?:encoding|coding)\s*:\s*[\w.-]+\b/i

        # Tool directives like:
        #   # :nocov:
        #   # :stopdoc:
        #   # :nodoc:
        return true if line =~ /^\s*#\s*:\s*[\w-]+\s*:(?=\s|\z)/i

        false
      end

      def doc_marker_line?(line)
        # Docscribe header line:
        #   # +A#foo+ -> Integer
        return true if line =~ /^\s*#\s*\+\S.*\+\s*->\s*\S/

        # YARD tags and directives:
        #   # @param ...
        #   # @return ...
        #   # @raise ...
        #   # @private / @protected
        #   # @!attribute ...
        # also matches indented attribute tag lines like:
        #   #   @return [Type]
        return true if line =~ /^\s*#\s*@/

        false
      end

      # Check whether there is a comment immediately above the method definition.
      #
      # Notes:
      # - This is intentionally simple: any line starting with `#` counts.
      # - Docscribe does not try to parse YARD tags here; it simply avoids overwriting user comments
      #   unless `rewrite` mode is enabled.
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

      def line_indent(node)
        line = node.loc.expression.source_line
        return '' unless line

        # Preserve tabs/spaces exactly.
        line[/\A[ \t]*/] || ''
      rescue StandardError
        ''
      end
    end
  end
end
