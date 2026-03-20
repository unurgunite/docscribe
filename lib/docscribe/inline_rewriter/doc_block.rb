# frozen_string_literal: true

module Docscribe
  module InlineRewriter
    # Text-preserving doc-block parsing and tag sorting helpers.
    #
    # This module operates on existing comment blocks and is used to:
    # - preserve user-authored tag text exactly
    # - append generated missing tag entries
    # - sort only configured sortable tags
    # - preserve boundaries such as prose comments and blank comment lines
    module DocBlock
      module_function

      # One parsed entry inside a doc block.
      #
      # `kind` is:
      # - `:tag` for a sortable top-level tag entry
      # - `:other` for prose/separators/non-sortable content
      Entry = Struct.new(
        :kind,
        :tag,
        :lines,
        :subject,
        :option_owner,
        :generated,
        :index,
        keyword_init: true
      )

      # Merge existing doc lines with newly generated missing tag lines.
      #
      # Existing text is preserved exactly. If sorting is enabled, only sortable tag runs
      # are normalized according to the configured tag order.
      #
      # @note module_function: when included, also defines #merge (instance visibility: private)
      # @param [Array<String>] existing_lines existing doc block lines
      # @param [Array<String>] missing_lines generated tag lines to add
      # @param [Boolean] sort_tags whether sortable tags should be reordered
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Array<String>]
      def merge(existing_lines, missing_lines:, sort_tags:, tag_order:)
        existing_entries = parse(existing_lines, tag_order: tag_order)
        missing_entries = parse_generated(missing_lines, tag_order: tag_order)

        entries = existing_entries + missing_entries
        entries = sort(entries, tag_order: tag_order) if sort_tags

        render(entries)
      end

      # Parse generated missing tag lines and mark them as generated entries.
      #
      # @note module_function: when included, also defines #parse_generated (instance visibility: private)
      # @param [Array<String>] lines generated lines
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Array<Entry>]
      def parse_generated(lines, tag_order:)
        parse(lines, tag_order: tag_order).map do |entry|
          entry.generated = true if entry.kind == :tag
          entry
        end
      end

      # Parse a doc block into structured entries.
      #
      # Only tags listed in `tag_order` are treated as sortable tag entries.
      # Other lines become `:other` entries and act as sort boundaries.
      #
      # @note module_function: when included, also defines #parse (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Array<Entry>]
      def parse(lines, tag_order:)
        sortable_tags = normalized_tag_order(tag_order)
        entries = []
        i = 0
        index = 0

        while i < lines.length
          line = lines[i]

          if sortable_top_level_tag_line?(line, sortable_tags)
            entry, i = consume_tag_entry(lines, i, index: index, sortable_tags: sortable_tags)
            entries << entry
          else
            entries << Entry.new(
              kind: :other,
              lines: [line],
              generated: false,
              index: index
            )
            i += 1
          end

          index += 1
        end

        entries
      end

      # Sort parsed entries by configured tag order, preserving boundaries between tag runs.
      #
      # @note module_function: when included, also defines #sort (instance visibility: private)
      # @param [Array<Entry>] entries parsed entries
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Array<Entry>]
      def sort(entries, tag_order:)
        out = []
        priority = build_priority(tag_order)
        i = 0

        while i < entries.length
          if entries[i].kind == :tag
            run = []
            while i < entries.length && entries[i].kind == :tag
              run << entries[i]
              i += 1
            end
            out.concat(sort_run(run, priority: priority))
          else
            out << entries[i]
            i += 1
          end
        end

        out
      end

      # Render parsed entries back into comment lines.
      #
      # @note module_function: when included, also defines #render (instance visibility: private)
      # @param [Array<Entry>] entries
      # @return [Array<String>]
      def render(entries)
        entries.flat_map(&:lines)
      end

      # Sort one contiguous run of sortable tag entries.
      #
      # @note module_function: when included, also defines #sort_run (instance visibility: private)
      # @param [Array<Entry>] entries contiguous tag run
      # @param [Hash{String=>Integer}] priority tag priority map
      # @return [Array<Entry>]
      def sort_run(entries, priority:)
        groups = build_groups(entries)

        groups
          .each_with_index
          .sort_by { |(group, idx)| [group_priority(group, priority), idx] }
          .map(&:first)
          .flatten
      end

      # Group entries so related `@option` tags stay attached to their owning `@param`.
      #
      # @note module_function: when included, also defines #build_groups (instance visibility: private)
      # @param [Array<Entry>] entries
      # @return [Array<Array<Entry>>]
      def build_groups(entries)
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
                  entries[i].option_owner == entry.subject
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

      # Compute the priority of a grouped sortable unit.
      #
      # @note module_function: when included, also defines #group_priority (instance visibility: private)
      # @param [Array<Entry>] group
      # @param [Hash{String=>Integer}] priority
      # @return [Integer]
      def group_priority(group, priority)
        priority.fetch(group.first.tag, priority.length)
      end

      # Build a tag priority map from configured order.
      #
      # @note module_function: when included, also defines #build_priority (instance visibility: private)
      # @param [Array<String>] tag_order
      # @return [Hash{String=>Integer}]
      def build_priority(tag_order)
        normalized_tag_order(tag_order).each_with_index.to_h
      end

      # Normalize configured tag names by removing leading `@`.
      #
      # @note module_function: when included, also defines #normalized_tag_order (instance visibility: private)
      # @param [Array<String>] tag_order
      # @return [Array<String>]
      def normalized_tag_order(tag_order)
        Array(tag_order).map { |t| t.to_s.sub(/\A@/, '') }
      end

      # Consume one sortable top-level tag entry and its continuation lines.
      #
      # Continuation lines are comment lines that belong to the same logical tag entry
      # until a new sortable tag line or a blank comment separator is encountered.
      #
      # @note module_function: when included, also defines #consume_tag_entry (instance visibility: private)
      # @param [Array<String>] lines
      # @param [Integer] start_idx
      # @param [Integer] index stable original index
      # @param [Array<String>] sortable_tags
      # @return [Array<(Entry, Integer)>] parsed entry and next index
      def consume_tag_entry(lines, start_idx, index:, sortable_tags:)
        first = lines[start_idx]
        tag = extract_tag(first)

        entry_lines = [first]
        i = start_idx + 1

        while i < lines.length
          line = lines[i]
          break if sortable_top_level_tag_line?(line, sortable_tags)
          break if blank_comment_line?(line)
          break unless continuation_comment_line?(line)

          entry_lines << line
          i += 1
        end

        entry = Entry.new(
          kind: :tag,
          tag: tag,
          lines: entry_lines,
          subject: extract_subject(first, tag),
          option_owner: extract_option_owner(first),
          generated: false,
          index: index
        )

        [entry, i]
      end

      # Extract the grouping subject for a sortable tag.
      #
      # Currently only `@param` entries carry a subject, used to keep `@option` tags attached.
      #
      # @note module_function: when included, also defines #extract_subject (instance visibility: private)
      # @param [String] line
      # @param [String] tag
      # @return [String, nil]
      def extract_subject(line, tag)
        case tag
        when 'param'
          extract_param_name(line)
        end
      end

      # Extract a parameter name from a `@param` line.
      #
      # Supports both:
      # - `@param [Type] name`
      # - `@param name [Type]`
      #
      # @note module_function: when included, also defines #extract_param_name (instance visibility: private)
      # @param [String] line
      # @return [String, nil]
      def extract_param_name(line)
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+\[[^\]]+\]\s+(\S+)/
        return Regexp.last_match(1) if line =~ /^\s*#\s*@param\b\s+(\S+)\s+\[[^\]]+\]/

        nil
      end

      # Extract the owning options-hash param name from an `@option` line.
      #
      # @note module_function: when included, also defines #extract_option_owner (instance visibility: private)
      # @param [String] line
      # @return [String, nil]
      def extract_option_owner(line)
        line[/^\s*#\s*@option\b\s+(\S+)/, 1]
      end

      # Whether a line is a sortable top-level tag line.
      #
      # @note module_function: when included, also defines #sortable_top_level_tag_line? (instance visibility: private)
      # @param [String] line
      # @param [Array<String>] sortable_tags
      # @return [Boolean]
      def sortable_top_level_tag_line?(line, sortable_tags)
        return false unless top_level_tag_line?(line)

        sortable_tags.include?(extract_tag(line))
      end

      # Extract a top-level tag name without the leading `@`.
      #
      # @note module_function: when included, also defines #extract_tag (instance visibility: private)
      # @param [String] line
      # @return [String, nil]
      def extract_tag(line)
        line[/^\s*#\s*@(\w+)/, 1]
      end

      # Whether a line begins a top-level YARD-style tag.
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

      # Whether a line is a blank comment separator such as `#`.
      #
      # @note module_function: when included, also defines #blank_comment_line? (instance visibility: private)
      # @param [String] line
      # @return [Boolean]
      def blank_comment_line?(line)
        !!(line =~ /^\s*#\s*$/)
      end

      # Whether a comment line should be treated as a continuation of the previous tag entry.
      #
      # @note module_function: when included, also defines #continuation_comment_line? (instance visibility: private)
      # @param [String] line
      # @return [Boolean]
      def continuation_comment_line?(line)
        !!(line =~ /^\s*#[ \t]{2,}\S/)
      end
    end
  end
end
