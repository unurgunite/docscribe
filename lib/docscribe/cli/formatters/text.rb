# frozen_string_literal: true

module Docscribe
  module CLI
    module Formatters
      # Text output formatter preserving the original CLI output format.
      class Text
        # Method documentation.
        #
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Hash<Symbol, Object>] options Param documentation.
        # @return [void]
        def format_check_summary(state:, options:)
          puts
          format_fail_paths(state, options)
          format_check_status_line(state)
          format_type_mismatch_paths(state, options)
          format_error_paths(state)
        end

        # Method documentation.
        #
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Hash<Symbol, Object>] options Param documentation.
        # @return [void]
        def format_write_summary(state:, options:)
          puts
          puts "Docscribe: updated #{state[:corrected]} file(s)" if state[:corrected].positive?
          format_corrected_paths(state, options)

          return unless state[:had_errors]

          warn "Docscribe: #{state[:error_paths].size} file(s) had errors"
          format_error_paths(state)
        end

        # Method documentation.
        #
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Object] options Param documentation.
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

        # Method documentation.
        #
        # @param [Hash<Symbol, Object>] state Param documentation.
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

        # Method documentation.
        #
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Object] options Param documentation.
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

        # Method documentation.
        #
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Object] options Param documentation.
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

        # Method documentation.
        #
        # @param [Hash<Symbol, Object>] state Param documentation.
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

        # Method documentation.
        #
        # @private
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Integer] checked_error Param documentation.
        # @param [Integer] type_mismatch_count Param documentation.
        # @return [Boolean]
        def all_fine?(state, checked_error, type_mismatch_count)
          state[:checked_fail].zero? && checked_error.zero? && type_mismatch_count.zero?
        end

        # Method documentation.
        #
        # @private
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Integer] checked_error Param documentation.
        # @return [Boolean]
        def mismatch_only?(state, checked_error)
          state[:checked_fail].zero? && checked_error.zero?
        end

        # Method documentation.
        #
        # @private
        # @param [Hash<Symbol, Object>] state Param documentation.
        # @param [Integer] type_mismatch_count Param documentation.
        # @param [Integer] checked_error Param documentation.
        # @return [String]
        def failure_line(state, type_mismatch_count, checked_error)
          parts = ["#{state[:checked_fail]} need updates"]
          parts << "#{type_mismatch_count} type mismatches" if type_mismatch_count.positive?
          parts << "#{checked_error} errors"
          parts << "#{state[:checked_ok]} ok"
          "Docscribe: FAILED (#{parts.join(', ')})"
        end

        # Method documentation.
        #
        # @private
        # @param [Hash<Symbol, Object>] change Param documentation.
        # @return [String]
        def format_change_reason(change)
          line = change_line_suffix(change)
          method = change_method_suffix(change)

          return "unsorted tags#{line}" if change[:type] == :unsorted_tags
          return "#{change[:message]}#{method}#{line}" if direct_message_change?(change)

          "#{change[:message] || change[:type].to_s.tr('_', ' ')}#{method}#{line}"
        end

        # Method documentation.
        #
        # @private
        # @param [Hash<Symbol, Object>] change Param documentation.
        # @return [String]
        def change_line_suffix(change)
          change[:line] ? " at line #{change[:line]}" : ''
        end

        # Method documentation.
        #
        # @private
        # @param [Hash<Symbol, Object>] change Param documentation.
        # @return [String]
        def change_method_suffix(change)
          change[:method] ? " for #{change[:method]}" : ''
        end

        # Method documentation.
        #
        # @private
        # @param [Hash<Symbol, Object>] change Param documentation.
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
