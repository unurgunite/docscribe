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

      # Method documentation.
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_priority (instance visibility: private)
      # @param [Array<String>] tag_order Param documentation.
      # @return [Hash<String, Integer>]
      def build_priority(tag_order)
        Array(tag_order).map { |t| t.to_s.sub(/\A@/, '') }
                        .each_with_index
                        .to_h
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #parse_segments (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @return [Array<Hash<Symbol, Object>>]
      def parse_segments(lines)
        segments = [] #: Array[untyped]
        i = 0

        i = advance_parse(lines, i, segments) while i < lines.length

        segments
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #advance_parse (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Integer] idx current parse index
      # @param [Array<Hash<Symbol, Object>>] segments accumulated parsed segments
      # @return [Integer] new index after processing
      def advance_parse(lines, idx, segments)
        if top_level_tag_line?(lines[idx])
          consume_tag_run(lines, idx, segments)
        else
          segments << { type: :other, lines: [lines[idx]] }
          idx + 1
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #consume_tag_run (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Integer] idx current index
      # @param [Array<Hash<Symbol, Object>>] segments accumulated segments
      # @return [Integer] new index after consuming the run
      def consume_tag_run(lines, idx, segments)
        entries = [] #: Array[untyped]
        while idx < lines.length && top_level_tag_line?(lines[idx])
          entry, idx = consume_entry(lines, idx)
          entries << entry
        end
        segments << { type: :tag_run, entries: entries }
        idx
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #sort_segment (instance visibility: private)
      # @param [Hash<Symbol, Object>] segment Param documentation.
      # @param [Hash<String, Integer>] priority Param documentation.
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #group_priority (instance visibility: private)
      # @param [Array<Object>] group Param documentation.
      # @param [Hash<String, Integer>] priority Param documentation.
      # @return [Integer]
      def group_priority(group, priority)
        first = group.first
        priority.fetch(first.tag, priority.length)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #consume_entry (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Integer] start_idx Param documentation.
      # @return [[ Object, ::Integer ]]
      def consume_entry(lines, start_idx)
        first = lines[start_idx]
        tag = extract_tag_name(first)
        entry_lines = collect_continuation_lines(lines, start_idx + 1)
        i = entry_lines.length + start_idx

        entry = build_entry(tag, entry_lines, first, start_idx)

        [entry, i]
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #build_entry (instance visibility: private)
      # @param [String, nil] tag the extracted tag name
      # @param [Array<String>] entry_lines all lines belonging to this entry
      # @param [String] first the first (tag) line
      # @param [Integer] start_idx original index of the first line
      # @return [Object]
      def build_entry(tag, entry_lines, first, start_idx)
        Entry.new(
          tag: tag,
          lines: entry_lines,
          param_name: extract_param_name(first),
          option_owner: extract_option_owner(first),
          index: start_idx
        )
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_continuation_lines (instance visibility: private)
      # @param [Array<String>] lines Param documentation.
      # @param [Integer] start_idx Param documentation.
      # @return [Array<String>]
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #group_entries (instance visibility: private)
      # @param [Array<Object>] entries Param documentation.
      # @return [Array<Array<Object>>]
      def group_entries(entries)
        groups = [] #: Array[untyped]
        i = 0

        while i < entries.length
          groups << group_entry(entries, i)
          i += 1
        end

        groups
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #group_entry (instance visibility: private)
      # @param [Array<Object>] entries parsed tag entries
      # @param [Integer] idx index of the entry to group
      # @return [Array<Object>] the entry group
      def group_entry(entries, idx)
        entry = entries[idx]
        if entry.tag == 'param'
          [entry] + collect_option_entries(entries, idx + 1, entry.param_name)
        else
          [entry]
        end
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #collect_option_entries (instance visibility: private)
      # @param [Array<Object>] entries Param documentation.
      # @param [Integer] start_idx Param documentation.
      # @param [String] param_name Param documentation.
      # @return [Array<Object>]
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

      # Method documentation.
      #
      # @note module_function: when included, also defines #top_level_tag_line? (instance visibility: private)
      # @param [String] line Param documentation.
      # @return [Boolean]
      def top_level_tag_line?(line)
        !!(line =~ /^\s*#\s*@\w+/)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #comment_line? (instance visibility: private)
      # @param [String] line Param documentation.
      # @return [Boolean]
      def comment_line?(line)
        !!(line =~ /^\s*#/)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #blank_comment_line? (instance visibility: private)
      # @param [String] line Param documentation.
      # @return [Boolean]
      def blank_comment_line?(line)
        !!(line =~ /^\s*#\s*$/)
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_tag_name (instance visibility: private)
      # @param [String] line Param documentation.
      # @return [String, nil]
      def extract_tag_name(line)
        line[/^\s*#\s*@(\w+)/, 1]
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_param_name (instance visibility: private)
      # @param [String] line Param documentation.
      # @return [String, nil]
      def extract_param_name(line)
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Method documentation.
      #
      # @note module_function: when included, also defines #extract_option_owner (instance visibility: private)
      # @param [String] line Param documentation.
      # @return [String, nil]
      def extract_option_owner(line)
        line[/^\s*#\s*@option\b\s+(\S+)/, 1]
      end
    end
  end
end
