# frozen_string_literal: true

module Docscribe
  module InlineRewriter
    # Older tag-sorting helper operating on comment-line segments.
    #
    # This module sorts contiguous runs of top-level tag entries and keeps related `@option`
    # entries attached to their owning `@param`.
    #
    # If `DocBlock` fully supersedes this module in your codebase, consider removing it.
    module TagSorter
      module_function

      # One sortable top-level tag entry plus its continuation lines.
      Entry = Struct.new(:tag, :lines, :param_name, :option_owner, :index, keyword_init: true)

      # Sort contiguous top-level tag runs according to configured tag order.
      #
      # Non-tag content is preserved as-is and acts as a sort boundary.
      #
      # @note module_function: when included, also defines #sort (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Array<String>] tag_order configured tag order
      # @return [Array<String>]
      def sort(lines, tag_order:)
        priority = build_priority(tag_order)
        segments = parse_segments(lines)
        segments.flat_map { |seg| sort_segment(seg, priority: priority) }
      end

      # Build a tag priority map from configured tag order.
      #
      # @note module_function: when included, also defines #build_priority (instance visibility: private)
      # @param [Array<String>] tag_order
      # @return [Hash{String=>Integer}]
      def build_priority(tag_order)
        Array(tag_order).map { |t| t.to_s.sub(/\A@/, '') }
                        .each_with_index
                        .to_h
      end

      # Parse lines into sortable tag-run segments and non-sortable segments.
      #
      # @note module_function: when included, also defines #parse_segments (instance visibility: private)
      # @param [Array<String>] lines
      # @return [Array<Hash>]
      def parse_segments(lines)
        segments = []
        i = 0

        while i < lines.length
          line = lines[i]

          if top_level_tag_line?(line)
            entries = []
            while i < lines.length && top_level_tag_line?(lines[i])
              entry, i = consume_entry(lines, i)
              entries << entry
            end
            segments << { type: :tag_run, entries: entries }
          else
            segments << { type: :other, lines: [line] }
            i += 1
          end
        end

        segments
      end

      # Sort one parsed segment if it is a tag run.
      #
      # @note module_function: when included, also defines #sort_segment (instance visibility: private)
      # @param [Hash] segment
      # @param [Hash{String=>Integer}] priority
      # @return [Array<String>]
      def sort_segment(segment, priority:)
        return segment[:lines] unless segment[:type] == :tag_run

        groups = group_entries(segment[:entries])

        groups
          .each_with_index
          .sort_by { |(group, idx)| [group_priority(group, priority), idx] }
          .flat_map(&:first)
          .flat_map(&:lines)
      end

      # Compute sort priority for a grouped tag entry.
      #
      # @note module_function: when included, also defines #group_priority (instance visibility: private)
      # @param [Array<Entry>] group
      # @param [Hash{String=>Integer}] priority
      # @return [Integer]
      def group_priority(group, priority)
        first = group.first
        priority.fetch(first.tag, priority.length)
      end

      # Consume one top-level tag entry and its continuation lines.
      #
      # @note module_function: when included, also defines #consume_entry (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Integer] start_idx
      # @return [Array<(Entry, Integer)>]
      def consume_entry(lines, start_idx)
        first = lines[start_idx]
        tag = extract_tag_name(first)
        entry_lines = [first]
        i = start_idx + 1

        while i < lines.length
          line = lines[i]

          break if top_level_tag_line?(line)
          break if blank_comment_line?(line)
          break unless comment_line?(line)

          entry_lines << line
          i += 1
        end

        entry = Entry.new(
          tag: tag,
          lines: entry_lines,
          param_name: extract_param_name(first),
          option_owner: extract_option_owner(first),
          index: start_idx
        )

        [entry, i]
      end

      # Group entries so `@option` tags remain attached to their owning `@param`.
      #
      # @note module_function: when included, also defines #group_entries (instance visibility: private)
      # @param [Array<Entry>] entries
      # @return [Array<Array<Entry>>]
      def group_entries(entries)
        groups = []
        i = 0

        while i < entries.length
          entry = entries[i]

          if entry.tag == 'param'
            group = [entry]
            i += 1

            while i < entries.length &&
                  entries[i].tag == 'option' &&
                  entries[i].option_owner &&
                  entries[i].option_owner == entry.param_name
              group << entries[i]
              i += 1
            end

            groups << group
          else
            groups << [entry]
            i += 1
          end
        end

        groups
      end

      # Whether a line begins a top-level tag entry.
      #
      # @note module_function: when included, also defines #top_level_tag_line? (instance visibility: private)
      # @param [String] line
      # @return [Boolean]
      def top_level_tag_line?(line)
        !!(line =~ /^\s*#\s*@\w+/)
      end

      # Whether a line is any comment line.
      #
      # @note module_function: when included, also defines #comment_line? (instance visibility: private)
      # @param [String] line
      # @return [Boolean]
      def comment_line?(line)
        !!(line =~ /^\s*#/)
      end

      # Whether a line is a blank comment separator.
      #
      # @note module_function: when included, also defines #blank_comment_line? (instance visibility: private)
      # @param [String] line
      # @return [Boolean]
      def blank_comment_line?(line)
        !!(line =~ /^\s*#\s*$/)
      end

      # Extract tag name from a top-level tag line without the leading `@`.
      #
      # @note module_function: when included, also defines #extract_tag_name (instance visibility: private)
      # @param [String] line
      # @return [String, nil]
      def extract_tag_name(line)
        line[/^\s*#\s*@(\w+)/, 1]
      end

      # Extract parameter name from a `@param` line.
      #
      # @note module_function: when included, also defines #extract_param_name (instance visibility: private)
      # @param [String] line
      # @return [String, nil]
      def extract_param_name(line)
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Extract owning options-hash param name from an `@option` line.
      #
      # @note module_function: when included, also defines #extract_option_owner (instance visibility: private)
      # @param [String] line
      # @return [String, nil]
      def extract_option_owner(line)
        line[/^\s*#\s*@option\b\s+(\S+)/, 1]
      end
    end
  end
end
