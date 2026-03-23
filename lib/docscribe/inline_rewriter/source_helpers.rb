# frozen_string_literal: true

require 'parser/source/range'

module Docscribe
  module InlineRewriter
    # Source-level helpers: ranges, insertion positions, indentation, and comment-block detection.
    #
    # These helpers operate on raw source text and parser source locations rather than Ruby semantics.
    module SourceHelpers
      module_function

      # Extract the method name from a `:def` or `:defs` node.
      #
      # @note module_function: when included, also defines #node_name (instance visibility: private)
      # @param [Parser::AST::Node] node
      # @return [Symbol, nil]
      def node_name(node)
        case node.type
        when :def then node.children[0]
        when :defs then node.children[1]
        end
      end

      # Return a zero-width range at the beginning of the line containing a node.
      #
      # Used as the insertion point for generated documentation.
      #
      # @note module_function: when included, also defines #line_start_range (instance visibility: private)
      # @param [Parser::Source::Buffer] buffer
      # @param [Parser::AST::Node] node
      # @return [Parser::Source::Range]
      def line_start_range(buffer, node)
        start_pos = node.loc.expression.begin_pos
        src = buffer.source
        bol = src.rindex("\n", start_pos - 1) || -1
        Parser::Source::Range.new(buffer, bol + 1, bol + 1)
      end

      # Return structured information about a contiguous doc-like comment block above a method.
      #
      # Result includes:
      # - all lines in the contiguous block
      # - preserved directive prefix lines
      # - editable doc lines
      # - source positions for replacement
      #
      # Returns nil if no doc-like block is present.
      #
      # @note module_function: when included, also defines #doc_comment_block_info (instance visibility: private)
      # @param [Parser::Source::Buffer] buffer
      # @param [Integer] def_bol_pos beginning-of-line position of the target def
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
        end_idx = i
        start_idx = i
        start_idx -= 1 while start_idx >= 0 && lines[start_idx] =~ /^\s*#/
        start_idx += 1

        # Preserve leading directive-style comments
        removable_start_idx = start_idx
        removable_start_idx += 1 while removable_start_idx <= end_idx && preserved_comment_line?(lines[removable_start_idx])

        return nil if removable_start_idx > end_idx

        remaining = lines[removable_start_idx..end_idx]
        return nil unless remaining.any? { |line| doc_marker_line?(line) }

        start_pos = start_idx.positive? ? lines[0...start_idx].join.length : 0
        doc_start_pos = removable_start_idx.positive? ? lines[0...removable_start_idx].join.length : 0
        end_pos = lines[0..end_idx].join.length

        {
          lines: lines[start_idx..end_idx],
          preserved_lines: lines[start_idx...removable_start_idx],
          doc_lines: lines[removable_start_idx..end_idx],
          start_pos: start_pos,
          doc_start_pos: doc_start_pos,
          end_pos: end_pos
        }
      end

      # Compute the removable range for an existing doc-like block above a method.
      #
      # Preserved directive lines (such as RuboCop directives or magic comments) are excluded
      # from the returned range.
      #
      # @note module_function: when included, also defines #comment_block_removal_range (instance visibility: private)
      # @param [Parser::Source::Buffer] buffer
      # @param [Integer] def_bol_pos beginning-of-line position of the target def
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

      # Whether a comment line should be preserved during aggressive replacement.
      #
      # Preserved lines include:
      # - RuboCop directives
      # - Ruby magic comments
      # - tool directives such as `:nocov:` / `:stopdoc:`
      #
      # @note module_function: when included, also defines #preserved_comment_line? (instance visibility: private)
      # @param [String] line
      # @return [Boolean]
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

      # Whether a comment line looks like documentation content.
      #
      # Recognized forms include:
      # - Docscribe header lines
      # - YARD tags/directives beginning with `@`
      #
      # @note module_function: when included, also defines #doc_marker_line? (instance visibility: private)
      # @param [String] line
      # @return [Boolean]
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

      # Whether any comment exists immediately above the insertion point.
      #
      # This helper is retained for compatibility/legacy behavior checks.
      #
      # @note module_function: when included, also defines #already_has_doc_immediately_above? (instance visibility: private)
      # @param [Parser::Source::Buffer] buffer
      # @param [Integer] insert_pos
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

      # Return the indentation prefix of a node's source line.
      #
      # Tabs and spaces are preserved exactly.
      #
      # @note module_function: when included, also defines #line_indent (instance visibility: private)
      # @param [Parser::AST::Node] node
      # @raise [StandardError]
      # @return [String]
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
