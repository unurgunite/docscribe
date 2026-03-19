# frozen_string_literal: true

module Docscribe
  module InlineRewriter
    module TagSorter
      module_function

      Entry = Struct.new(:tag, :lines, :param_name, :option_owner, :index, keyword_init: true)

      # Reorder sortable tags inside contiguous tag runs.
      #
      # Rules:
      # - only top-level YARD tags are sortable
      # - blank comment lines (`#`) split runs
      # - non-tag comment text splits runs
      # - multiline tag entries move as a unit
      # - @option entries stay attached to their owning @param when possible
      #
      # @param lines [Array<String>]
      # @param tag_order [Array<String>]
      # @return [Array<String>]
      def sort(lines, tag_order:)
        priority = build_priority(tag_order)
        segments = parse_segments(lines)
        segments.flat_map { |seg| sort_segment(seg, priority: priority) }
      end

      def build_priority(tag_order)
        Array(tag_order).map { |t| t.to_s.sub(/\A@/, '') }
                        .each_with_index
                        .to_h
      end

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

      def sort_segment(segment, priority:)
        return segment[:lines] unless segment[:type] == :tag_run

        groups = group_entries(segment[:entries])

        groups
          .each_with_index
          .sort_by { |(group, idx)| [group_priority(group, priority), idx] }
          .flat_map(&:first)
          .flat_map(&:lines)
      end

      def group_priority(group, priority)
        first = group.first
        priority.fetch(first.tag, priority.length)
      end

      def consume_entry(lines, start_idx)
        first = lines[start_idx]
        tag = extract_tag_name(first)
        entry_lines = [first]
        i = start_idx + 1

        while i < lines.length
          line = lines[i]

          break if top_level_tag_line?(line)
          break if blank_comment_line?(line)

          # Any non-tag comment line immediately following a tag belongs to that tag entry.
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

      def top_level_tag_line?(line)
        !!(line =~ /^\s*#\s*@\w+/)
      end

      def comment_line?(line)
        !!(line =~ /^\s*#/)
      end

      def blank_comment_line?(line)
        !!(line =~ /^\s*#\s*$/)
      end

      def extract_tag_name(line)
        line[/^\s*#\s*@(\w+)/, 1]
      end

      # Supports:
      #   # @param [Type] name desc
      #   # @param name [Type] desc
      def extract_param_name(line)
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Supports:
      #   # @option opts [String] :foo desc
      def extract_option_owner(line)
        line[/^\s*#\s*@option\b\s+(\S+)/, 1]
      end
    end
  end
end
