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

      # @!attribute [rw] kind
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] tag
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] lines
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] subject
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] option_owner
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] generated
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] index
      #   @return [Object]
      #   @param [Object] value
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
      # @param [Hash<Symbol, Object>] filter_existing tags to filter from existing block
      # @return [Array<String>]
      def merge(existing_lines, missing_lines:, sort_tags:, tag_order:, filter_existing: {})
        existing_entries = parse(existing_lines, tag_order: tag_order)
        missing_entries = parse_generated(missing_lines, tag_order: tag_order)
        existing_entries = filter_existing_entries(existing_entries, filter_existing)
        entries = existing_entries + missing_entries
        entries = sort(entries, tag_order: tag_order) if sort_tags
        render(entries)
      end

      # Parse generated missing tag lines and mark them as generated entries.
      #
      # @note module_function: when included, also defines #parse_generated (instance visibility: private)
      # @param [Array<String>] lines generated lines
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Array<Object>]
      def parse_generated(lines, tag_order:)
        parse(lines, tag_order: tag_order).map do |entry|
          entry.generated = true if entry.kind == :tag
          entry
        end
      end

      # Remove existing entries matching the filter criteria (param names or return tag).
      #
      # @note module_function: when included, also defines #filter_existing_entries (instance visibility: private)
      # @param [Array<Object>] entries parsed existing entries
      # @param [Hash<Symbol, Object>] filter_existing filter specification with :param_names and :return keys
      # @return [Array<Object>] filtered entries
      def filter_existing_entries(entries, filter_existing)
        filter_param_names = filter_existing[:param_names] || []
        filter_return = !!filter_existing[:return]
        entries.reject do |entry|
          filter_param_entry?(entry, filter_param_names) || filter_return_entry?(entry, filter_return)
        end
      end

      # Check whether an entry is a @param tag whose name is in the filter list.
      #
      # @note module_function: when included, also defines #filter_param_entry? (instance visibility: private)
      # @param [Object] entry the entry to check
      # @param [Array<String>] param_names parameter names to filter
      # @return [Boolean]
      def filter_param_entry?(entry, param_names)
        entry.kind == :tag && entry.tag == 'param' && param_names.include?(entry.subject)
      end

      # Check whether an entry is a @return tag that should be filtered.
      #
      # @note module_function: when included, also defines #filter_return_entry? (instance visibility: private)
      # @param [Object] entry the entry to check
      # @param [Boolean] filter_return whether return tags should be filtered
      # @return [Boolean]
      def filter_return_entry?(entry, filter_return)
        entry.kind == :tag && entry.tag == 'return' && filter_return
      end

      # Parse a doc block into structured entries.
      #
      # Only tags listed in `tag_order` are treated as sortable tag entries.
      # Other lines become `:other` entries and act as sort boundaries.
      #
      # @note module_function: when included, also defines #parse (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Array<Object>]
      def parse(lines, tag_order:)
        sortable_tags = normalized_tag_order(tag_order)
        parse_lines(lines, sortable_tags, entries: [], index: 0)
      end

      # Iterate through all lines and parse each one into a structured entry.
      #
      # @note module_function: when included, also defines #parse_lines (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Array<String>] sortable_tags tag names treated as sortable
      # @param [Array<Object>] entries accumulated parsed entries
      # @param [Integer] index stable ordering index for entries
      # @return [Array<Object>]
      def parse_lines(lines, sortable_tags, entries:, index:)
        idx = 0
        while idx < lines.length
          idx = parse_one_line(lines, idx, sortable_tags, entries, index)
          index += 1
        end
        entries
      end

      # Parse a single line as a sortable tag entry or non-tag content.
      #
      # @note module_function: when included, also defines #parse_one_line (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Integer] idx current line index
      # @param [Array<String>] sortable_tags tag names treated as sortable
      # @param [Array<Object>] entries accumulated parsed entries
      # @param [Integer] index stable ordering index for entries
      # @return [Integer] next line index after parsing
      def parse_one_line(lines, idx, sortable_tags, entries, index)
        if sortable_top_level_tag_line?(lines[idx], sortable_tags)
          entry, idx = consume_tag_entry(lines, idx, index: index, sortable_tags: sortable_tags)
          entries << entry
        else
          entries << build_other_entry(lines[idx], index)
          idx += 1
        end
        idx
      end

      # Create an :other entry for a non-tag line (prose, blank separators, etc.).
      #
      # @note module_function: when included, also defines #build_other_entry (instance visibility: private)
      # @param [String] line the comment line
      # @param [Integer] index stable ordering index
      # @return [Object]
      def build_other_entry(line, index)
        Entry.new(kind: :other, lines: [line], generated: false, index: index)
      end

      # Sort parsed entries by configured tag order, preserving boundaries between tag runs.
      #
      # @note module_function: when included, also defines #sort (instance visibility: private)
      # @param [Array<Object>] entries parsed entries
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Array<Object>]
      def sort(entries, tag_order:)
        out = [] #: Array[untyped]
        priority = build_priority(tag_order)
        sort_loop(entries, out, priority)
        out
      end

      # Iterate entries, sorting contiguous tag runs while preserving non-tag boundaries.
      #
      # @note module_function: when included, also defines #sort_loop (instance visibility: private)
      # @param [Array<Object>] entries parsed entries to sort
      # @param [Array<Object>] out output array for sorted entries
      # @param [Hash<String, Integer>] priority tag priority map
      # @return [void]
      def sort_loop(entries, out, priority)
        idx = 0

        while idx < entries.length
          if entries[idx].kind == :tag
            run, idx = consume_tag_run(entries, idx)
            out.concat(sort_run(run, priority: priority))
          else
            out << entries[idx]
            idx += 1
          end
        end
      end

      # Collect a contiguous run of :tag entries starting at idx.
      #
      # @note module_function: when included, also defines #consume_tag_run (instance visibility: private)
      # @param [Array<Object>] entries parsed entries
      # @param [Integer] idx start index
      # @return [(Array<Object>, Integer)]
      def consume_tag_run(entries, idx)
        run = [] #: Array[untyped]
        while idx < entries.length && entries[idx].kind == :tag
          run << entries[idx]
          idx += 1
        end
        [run, idx]
      end

      # Render parsed entries back into comment lines.
      #
      # @note module_function: when included, also defines #render (instance visibility: private)
      # @param [Array<Object>] entries contiguous tag run entries
      # @return [Array<String>]
      def render(entries)
        entries.flat_map(&:lines)
      end

      # Sort one contiguous run of sortable tag entries.
      #
      # @note module_function: when included, also defines #sort_run (instance visibility: private)
      # @param [Array<Object>] entries contiguous tag run
      # @param [Hash<String, Integer>] priority tag priority map
      # @return [Array<Object>]
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
      # @param [Array<Object>] entries contiguous tag run entries
      # @return [Array<Array<Object>>]
      def build_groups(entries)
        groups = [] #: Array[untyped]
        group_entries_loop(entries, groups)
        groups
      end

      # Iterate entries to build sorted groups, attaching @option entries to their @param.
      #
      # @note module_function: when included, also defines #group_entries_loop (instance visibility: private)
      # @param [Array<Object>] entries contiguous tag run entries
      # @param [Array<Array<Object>>] groups accumulated groups
      # @return [void]
      def group_entries_loop(entries, groups)
        idx = 0
        idx = group_one_entry(entries, idx, groups) while idx < entries.length
      end

      # Group a single entry, creating a param group with @option children if applicable.
      #
      # @note module_function: when included, also defines #group_one_entry (instance visibility: private)
      # @param [Array<Object>] entries contiguous tag run entries
      # @param [Integer] idx current entry index
      # @param [Array<Array<Object>>] groups accumulated groups
      # @return [Integer] next index after processing the group
      def group_one_entry(entries, idx, groups)
        entry = entries[idx]
        if entry.tag == 'param'
          group = build_param_group(entries, idx, entry)
          groups << group
          idx + group.size
        else
          groups << [entry]
          idx + 1
        end
      end

      # Build a group starting with a @param entry and including its following @option entries.
      #
      # @note module_function: when included, also defines #build_param_group (instance visibility: private)
      # @param [Array<Object>] entries contiguous tag run entries
      # @param [Integer] idx index of the @param entry
      # @param [Object] entry the @param entry
      # @return [Array<Object>] the param group including @option children
      def build_param_group(entries, idx, entry)
        group = [entry]
        idx += 1

        while idx < entries.length &&
              entries[idx].tag == 'option' &&
              entries[idx].option_owner &&
              entries[idx].option_owner == entry.subject
          group << entries[idx]
          idx += 1
        end

        group
      end

      # Compute the priority of a grouped sortable unit.
      #
      # @note module_function: when included, also defines #group_priority (instance visibility: private)
      # @param [Array<Object>] group
      # @param [Hash<String, Integer>] priority tag priority map
      # @return [Integer]
      def group_priority(group, priority)
        priority.fetch(group.first.tag, priority.length)
      end

      # Build a tag priority map from configured order.
      #
      # @note module_function: when included, also defines #build_priority (instance visibility: private)
      # @param [Array<String>] tag_order configured sortable tag order
      # @return [Hash<String, Integer>]
      def build_priority(tag_order)
        normalized_tag_order(tag_order).each_with_index.to_h
      end

      # Normalize configured tag names by removing leading `@`.
      #
      # @note module_function: when included, also defines #normalized_tag_order (instance visibility: private)
      # @param [Array<String>] tag_order configured sortable tag order
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
      # @param [Array<String>] lines comment block lines
      # @param [Integer] start_idx index to start scanning from
      # @param [Integer] index stable original index
      # @param [Array<String>] sortable_tags tag names treated as sortable
      # @return [(Object, Integer)]
      def consume_tag_entry(lines, start_idx, index:, sortable_tags:)
        first = lines[start_idx]
        tag = extract_tag(first)
        entry_lines = collect_continuation_lines(lines, start_idx + 1, first, sortable_tags)
        i = entry_lines.length + start_idx
        entry = build_tag_entry(first, tag, entry_lines, index)
        [entry, i]
      end

      # Collect the first tag line and all continuation lines belonging to the same entry.
      #
      # @note module_function: when included, also defines #collect_continuation_lines (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Integer] start_idx index after the tag line
      # @param [String] first the tag line itself
      # @param [Array<String>] sortable_tags tag names treated as sortable
      # @return [Array<String>] all lines belonging to this entry
      def collect_continuation_lines(lines, start_idx, first, sortable_tags)
        result = [first]
        add_continuation_lines(lines, start_idx, result, sortable_tags)
        result
      end

      # Append continuation lines to the result array until a non-continuation line is found.
      #
      # @note module_function: when included, also defines #add_continuation_lines (instance visibility: private)
      # @param [Array<String>] lines comment block lines
      # @param [Integer] start_idx index to start scanning from
      # @param [Array<String>] result accumulated entry lines
      # @param [Array<String>] sortable_tags tag names treated as sortable
      # @return [void]
      def add_continuation_lines(lines, start_idx, result, sortable_tags)
        i = start_idx
        while i < lines.length
          line = lines[i]
          break unless continuation_candidate?(line, sortable_tags)

          result << line
          i += 1
        end
      end

      # Check whether a line can serve as a continuation of the current tag entry.
      #
      # @note module_function: when included, also defines #continuation_candidate? (instance visibility: private)
      # @param [String] line the line to check
      # @param [Array<String>] sortable_tags tag names treated as sortable
      # @return [Boolean]
      def continuation_candidate?(line, sortable_tags)
        !sortable_top_level_tag_line?(line, sortable_tags) &&
          !blank_comment_line?(line) &&
          continuation_comment_line?(line)
      end

      # Build a tag Entry struct with metadata from the parsed tag line and continuation lines.
      #
      # @note module_function: when included, also defines #build_tag_entry (instance visibility: private)
      # @param [String] first the first (tag) line
      # @param [String?] tag the extracted tag name
      # @param [Array<String>] entry_lines all lines belonging to this entry
      # @param [Integer] index stable ordering index
      # @return [Object]
      def build_tag_entry(first, tag, entry_lines, index)
        Entry.new(
          kind: :tag,
          tag: tag,
          lines: entry_lines,
          subject: extract_subject(first, tag),
          option_owner: extract_option_owner(first),
          generated: false,
          index: index
        )
      end

      # Extract the grouping subject for a sortable tag.
      #
      # Currently only `@param` entries carry a subject, used to keep `@option` tags attached.
      #
      # @note module_function: when included, also defines #extract_subject (instance visibility: private)
      # @param [String] line the line to check
      # @param [String?] tag the extracted tag name
      # @return [String?]
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
      # @param [String] line the line to check
      # @return [String?]
      def extract_param_name(line)
        content = line.sub(/^\s*#\s*/, '')
        if (m = content.match(/@param\s+(\S+)\s+\[/))
          return m[1]
        elsif (m = content.match(/@param\s+\[/))
          end0 = m.end(0) #: Integer
          rest = content[(end0 - 1)..] #: String
          type_end = matching_close_bracket(rest)
          return name_after_bracket(rest, type_end) if type_end
        end

        nil
      end

      # @note module_function: when included, also defines #name_after_bracket (instance visibility: private)
      # @param [Object] rest
      # @param [Object] type_end
      # @return [Object]
      def name_after_bracket(rest, type_end)
        rest[(type_end + 1)..].to_s.strip.split(/\s+/).first
      end

      # Find the index of the matching close bracket for an outermost `[`.
      #
      # @note module_function: when included, also defines #matching_close_bracket (instance visibility: private)
      # @param [Object] str
      # @return [nil]
      def matching_close_bracket(str)
        depth = 0
        str.each_char.with_index do |c, i|
          case c
          when '[' then depth += 1
          when ']'
            depth -= 1
            return i if depth.zero?
          end
        end
        nil
      end

      # Extract the owning options-hash param name from an `@option` line.
      #
      # @note module_function: when included, also defines #extract_option_owner (instance visibility: private)
      # @param [String] line the line to check
      # @return [String?]
      def extract_option_owner(line)
        line[/^\s*#\s*@option\b\s+(\S+)/, 1]
      end

      # Whether a line is a sortable top-level tag line.
      #
      # @note module_function: when included, also defines #sortable_top_level_tag_line? (instance visibility: private)
      # @param [String] line the line to check
      # @param [Array<String>] sortable_tags tag names treated as sortable
      # @return [Boolean]
      def sortable_top_level_tag_line?(line, sortable_tags)
        return false unless top_level_tag_line?(line)

        sortable_tags.include?(extract_tag(line))
      end

      # Extract a top-level tag name without the leading `@`.
      #
      # @note module_function: when included, also defines #extract_tag (instance visibility: private)
      # @param [String] line the line to check
      # @return [String?]
      def extract_tag(line)
        line[/^\s*#\s*@(\w+)/, 1]
      end

      # Whether a line begins a top-level YARD-style tag.
      #
      # @note module_function: when included, also defines #top_level_tag_line? (instance visibility: private)
      # @param [String] line the line to check
      # @return [Boolean]
      def top_level_tag_line?(line)
        !!(line =~ /^\s*#\s*@\w+/)
      end

      # Whether a line is any comment line.
      #
      # @note module_function: when included, also defines #comment_line? (instance visibility: private)
      # @param [String] line the line to check
      # @return [Boolean]
      def comment_line?(line)
        !!(line =~ /^\s*#/)
      end

      # Whether a line is a blank comment separator such as `#`.
      #
      # @note module_function: when included, also defines #blank_comment_line? (instance visibility: private)
      # @param [String] line the line to check
      # @return [Boolean]
      def blank_comment_line?(line)
        !!(line =~ /^\s*#\s*$/)
      end

      # Whether a comment line should be treated as a continuation of the previous tag entry.
      #
      # @note module_function: when included, also defines #continuation_comment_line? (instance visibility: private)
      # @param [String] line the line to check
      # @return [Boolean]
      def continuation_comment_line?(line)
        !!(line =~ /^\s*#[ \t]{2,}\S/)
      end
    end
  end
end
