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

      # @!attribute [rw] tag
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] lines
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] param_name
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] option_owner
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] index
      #   @return [Object]
      #   @param [Object] value
      Entry = Struct.new(:tag, :lines, :param_name, :option_owner, :index, keyword_init: true)

      # Sort
      #
      # @note module_function: defines #sort (visibility: private)
      # @param [Object] lines comment block lines
      # @param [Object] tag_order configured tag order
      # @return [Object]
      def sort(lines, tag_order:)
        priority = build_priority(tag_order)
        segments = parse_segments(lines)
        segments.flat_map { |seg| sort_segment(seg, priority: priority) }
      end

      # Build priority
      #
      # @note module_function: defines #build_priority (visibility: private)
      # @param [Object] tag_order configured tag order
      # @return [Object]
      def build_priority(tag_order)
        Array(tag_order).map { |t| t.to_s.sub(/\A@/, '') }
                        .each_with_index
                        .to_h
      end

      # Parse segments
      #
      # @note module_function: defines #parse_segments (visibility: private)
      # @param [Object] lines comment block lines
      # @return [Array]
      def parse_segments(lines)
        segments = [] #: Array[untyped]
        i = 0

        i = advance_parse(lines, i, segments) while i < lines.length

        segments
      end

      # Advance parse
      #
      # @note module_function: defines #advance_parse (visibility: private)
      # @param [Object] lines comment block lines
      # @param [Object] idx current parse index
      # @param [Object] segments accumulated parsed segments
      # @return [Object, Integer] new index after processing
      def advance_parse(lines, idx, segments)
        if top_level_tag_line?(lines[idx])
          consume_tag_run(lines, idx, segments)
        else
          segments << { type: :other, lines: [lines[idx]] }
          idx + 1
        end
      end

      # Consume tag run
      #
      # @note module_function: defines #consume_tag_run (visibility: private)
      # @param [Object] lines comment block lines
      # @param [Object] idx current index
      # @param [Object] segments accumulated segments
      # @return [Object] new index after consuming the run
      def consume_tag_run(lines, idx, segments)
        entries = [] #: Array[untyped]
        while idx < lines.length && top_level_tag_line?(lines[idx])
          entry, idx = consume_entry(lines, idx)
          entries << entry
        end
        segments << { type: :tag_run, entries: entries }
        idx
      end

      # Sort segment
      #
      # @note module_function: defines #sort_segment (visibility: private)
      # @param [Object] segment Param documentation.
      # @param [Object] priority Param documentation.
      # @return [Object]
      def sort_segment(segment, priority:)
        return segment[:lines] unless segment[:type] == :tag_run

        groups = group_entries(segment[:entries])

        groups
          .each_with_index
          .sort_by { |(group, idx)| [group_priority(group, priority), idx] }
          .flat_map(&:first)
          .flat_map(&:lines)
      end

      # Group priority
      #
      # @note module_function: defines #group_priority (visibility: private)
      # @param [Object] group Param documentation.
      # @param [Object] priority Param documentation.
      # @return [Object]
      def group_priority(group, priority)
        first = group.first
        priority.fetch(first.tag, priority.length)
      end

      # Consume entry
      #
      # @note module_function: defines #consume_entry (visibility: private)
      # @param [Object] lines comment block lines
      # @param [Object] start_idx original index of the first line
      # @return [Array]
      def consume_entry(lines, start_idx)
        first = lines[start_idx]
        tag = extract_tag_name(first)
        entry_lines = collect_continuation_lines(lines, start_idx + 1)
        i = entry_lines.length + start_idx

        entry = build_entry(tag, entry_lines, first, start_idx)

        [entry, i]
      end

      # Build entry
      #
      # @note module_function: defines #build_entry (visibility: private)
      # @param [Object] tag the extracted tag name
      # @param [Object] entry_lines all lines belonging to this entry
      # @param [Object] first the first (tag) line
      # @param [Object] start_idx original index of the first line
      # @return [Entry]
      def build_entry(tag, entry_lines, first, start_idx)
        Entry.new(
          tag: tag,
          lines: entry_lines,
          param_name: extract_param_name(first),
          option_owner: extract_option_owner(first),
          index: start_idx
        )
      end

      # Collect continuation lines
      #
      # @note module_function: defines #collect_continuation_lines (visibility: private)
      # @param [Object] lines comment block lines
      # @param [Object] start_idx original index of the first line
      # @return [Array]
      def collect_continuation_lines(lines, start_idx)
        result = [] #: Array[String]
        i = start_idx

        while i < lines.length
          line = lines[i]
          break if top_level_tag_line?(line) || blank_comment_line?(line) || !comment_line?(line)

          result << line
          i += 1
        end

        result
      end

      # Group entries
      #
      # @note module_function: defines #group_entries (visibility: private)
      # @param [Object] entries parsed tag entries
      # @return [Array]
      def group_entries(entries)
        groups = [] #: Array[untyped]
        i = 0

        while i < entries.length
          groups << group_entry(entries, i)
          i += 1
        end

        groups
      end

      # Group entry
      #
      # @note module_function: defines #group_entry (visibility: private)
      # @param [Object] entries parsed tag entries
      # @param [Object] idx index of the entry to group
      # @return [Array<Elem, U>, Array] the entry group
      def group_entry(entries, idx)
        entry = entries[idx]
        if entry.tag == 'param'
          [entry] + collect_option_entries(entries, idx + 1, entry.param_name)
        else
          [entry]
        end
      end

      # Collect option entries
      #
      # @note module_function: defines #collect_option_entries (visibility: private)
      # @param [Object] entries parsed tag entries
      # @param [Object] start_idx original index of the first line
      # @param [Object] param_name Param documentation.
      # @return [Array]
      def collect_option_entries(entries, start_idx, param_name)
        result = [] #: Array[untyped]
        i = start_idx

        while i < entries.length &&
              entries[i].tag == 'option' &&
              entries[i].option_owner &&
              entries[i].option_owner == param_name
          result << entries[i]
          i += 1
        end

        result
      end

      # Top level tag line
      #
      # @note module_function: defines #top_level_tag_line? (visibility: private)
      # @param [Object] line Param documentation.
      # @return [Boolean]
      def top_level_tag_line?(line)
        !!(line =~ /^\s*#\s*@\w+/)
      end

      # Comment line
      #
      # @note module_function: defines #comment_line? (visibility: private)
      # @param [Object] line Param documentation.
      # @return [Boolean]
      def comment_line?(line)
        !!(line =~ /^\s*#/)
      end

      # Blank comment line
      #
      # @note module_function: defines #blank_comment_line? (visibility: private)
      # @param [Object] line Param documentation.
      # @return [Boolean]
      def blank_comment_line?(line)
        !!(line =~ /^\s*#\s*$/)
      end

      # Extract tag name
      #
      # @note module_function: defines #extract_tag_name (visibility: private)
      # @param [Object] line Param documentation.
      # @return [Object]
      def extract_tag_name(line)
        line[/^\s*#\s*@(\w+)/, 1]
      end

      # Extract param name
      #
      # @note module_function: defines #extract_param_name (visibility: private)
      # @param [Object] line Param documentation.
      # @return [nil]
      def extract_param_name(line)
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Extract option owner
      #
      # @note module_function: defines #extract_option_owner (visibility: private)
      # @param [Object] line Param documentation.
      # @return [Object]
      def extract_option_owner(line)
        line[/^\s*#\s*@option\b\s+(\S+)/, 1]
      end
    end
  end
end
