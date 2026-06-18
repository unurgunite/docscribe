# frozen_string_literal: true

module Docscribe
  module CLI
    module Formatters
      # Text output formatter preserving the original CLI output format.
      class Text
        # Format and print check summary.
        #
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Docscribe::CLI::Formatters::opts] options runtime options hash
        # @return [void]
        def format_check_summary(state:, options:)
          puts
          format_fail_paths(state, options)
          format_check_status_line(state)
          format_type_mismatch_paths(state, options)
          format_error_paths(state)
        end

        # Format and print write summary.
        #
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Docscribe::CLI::Formatters::opts] options runtime options hash
        # @return [void]
        def format_write_summary(state:, options:)
          puts
          puts "Docscribe: updated #{state[:corrected]} file(s)" if state[:corrected].positive?
          format_corrected_paths(state, options)

          return unless state[:had_errors]

          warn "Docscribe: #{state[:error_paths].size} file(s) had errors"
          format_error_paths(state)
        end

        # Print files needing updates.
        #
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Docscribe::CLI::Formatters::opts] options runtime options hash
        # @return [void]
        def format_fail_paths(state, options)
          state[:fail_paths].each do |p|
            puts "Would update: #{p}"

            next if options[:verbose] || options[:quiet]

            Array(state[:fail_changes][p]).each do |change|
              puts "  - #{format_change_reason(change)}"
            end
          end
        end

        # Print check status line.
        #
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @return [void]
        def format_check_status_line(state)
          checked_error = state[:error_paths].size
          type_mismatch_count = state[:type_mismatch_paths].size

          if all_fine?(state, checked_error, type_mismatch_count)
            puts "Docscribe: OK (#{state[:checked_ok]} files checked)"
          elsif mismatch_only?(state, checked_error)
            puts "Docscribe: OK (#{state[:checked_ok]} files checked, #{type_mismatch_count} with type mismatches)"
          else
            puts failure_line(state, type_mismatch_count, checked_error)
          end
        end

        # Print type mismatch warnings.
        #
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Docscribe::CLI::Formatters::opts] options runtime options hash
        # @return [void]
        def format_type_mismatch_paths(state, options)
          return if options[:quiet]
          return unless options[:verbose] || options[:explain]

          state[:type_mismatch_paths].each do |p|
            warn "Type mismatches: #{p}"
            Array(state[:type_mismatch_changes][p]).each do |change|
              warn "  - #{format_change_reason(change)}"
            end
          end
        end

        # Print updated file paths.
        #
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Docscribe::CLI::Formatters::opts] options runtime options hash
        # @return [void]
        def format_corrected_paths(state, options)
          state[:corrected_paths].each do |p|
            puts "Updated: #{p}"

            next if options[:verbose] || options[:quiet]

            Array(state[:corrected_changes][p]).each do |change|
              puts "  - #{format_change_reason(change)}"
            end
          end
        end

        # Print error file messages.
        #
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @return [void]
        def format_error_paths(state)
          return if state[:error_paths].empty?

          warn ''
          state[:error_paths].each do |p|
            warn "Error processing: #{p}"
            warn "  #{state[:error_messages][p]}" if state[:error_messages][p]
          end
        end

        private

        # Check if all files passed.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Integer] checked_error count of error files
        # @param [Integer] type_mismatch_count count of type mismatches
        # @return [Boolean]
        def all_fine?(state, checked_error, type_mismatch_count)
          state[:checked_fail].zero? && checked_error.zero? && type_mismatch_count.zero?
        end

        # Check only type mismatches.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Integer] checked_error count of error files
        # @return [Boolean]
        def mismatch_only?(state, checked_error)
          state[:checked_fail].zero? && checked_error.zero?
        end

        # Build failure status line.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state formatter state hash
        # @param [Integer] type_mismatch_count count of type mismatches
        # @param [Integer] checked_error count of error files
        # @return [String]
        def failure_line(state, type_mismatch_count, checked_error)
          parts = ["#{state[:checked_fail]} need updates"]
          parts << "#{type_mismatch_count} type mismatches" if type_mismatch_count.positive?
          parts << "#{checked_error} errors"
          parts << "#{state[:checked_ok]} ok"
          "Docscribe: FAILED (#{parts.join(', ')})"
        end

        # Format change reason string.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change change info hash
        # @return [String]
        def format_change_reason(change)
          line = change_line_suffix(change)
          method = change_method_suffix(change)

          return "unsorted tags#{line}" if change[:type] == :unsorted_tags
          return "#{change[:message]}#{method}#{line}" if direct_message_change?(change)

          "#{change[:message] || change[:type].to_s.tr('_', ' ')}#{method}#{line}"
        end

        # Build change line suffix.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change change info hash
        # @return [String]
        def change_line_suffix(change)
          change[:line] ? " at line #{change[:line]}" : ''
        end

        # Build change method suffix.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change change info hash
        # @return [String]
        def change_method_suffix(change)
          change[:method] ? " for #{change[:method]}" : ''
        end

        # Check direct message type.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change change info hash
        # @return [Boolean]
        def direct_message_change?(change)
          %i[
            missing_param
            missing_return
            missing_raise
            missing_visibility
            missing_module_function_note
            insert_full_doc_block
          ].include?(change[:type])
        end
      end
    end
  end
end
