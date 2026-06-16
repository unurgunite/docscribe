# frozen_string_literal: true

require 'json'
require 'docscribe/version'

module Docscribe
  module CLI
    module Formatters
      # Output formatter producing RuboCop-compatible JSON.
      #
      # stdout: complete JSON document with all findings.
      # stderr: progress markers only (same as text mode).
      class Json
        SEVERITY_MAP = {
          missing_param: 'convention',
          missing_return: 'convention',
          missing_raise: 'convention',
          missing_visibility: 'convention',
          missing_module_function_note: 'convention',
          insert_full_doc_block: 'convention',
          unsorted_tags: 'convention',
          updated_param: 'warning',
          updated_return: 'warning'
        }.freeze

        COP_NAME_MAP = {
          missing_param: 'Docscribe/MissingParam',
          missing_return: 'Docscribe/MissingReturn',
          missing_raise: 'Docscribe/MissingRaise',
          missing_visibility: 'Docscribe/MissingVisibility',
          missing_module_function_note: 'Docscribe/MissingModuleFunctionNote',
          insert_full_doc_block: 'Docscribe/MissingDocBlock',
          unsorted_tags: 'Docscribe/UnsortedTags',
          updated_param: 'Docscribe/UpdatedParam',
          updated_return: 'Docscribe/UpdatedReturn'
        }.freeze

        # Method documentation.
        #
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @param [Docscribe::CLI::Formatters::opts] options Param documentation.
        # @return [void]
        def format_check_summary(state:, options:)
          puts JSON.generate(build_document(state, options))
        end

        # Method documentation.
        #
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @param [Docscribe::CLI::Formatters::opts] options Param documentation.
        # @return [void]
        def format_write_summary(state:, options:)
          puts JSON.generate(build_document(state, options))
        end

        private

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @param [Docscribe::CLI::Formatters::opts] _options Param documentation.
        # @return [Hash<Object, Object>]
        def build_document(state, _options)
          document_hash(build_files(state), state)
        end

        # Method documentation.
        #
        # @private
        # @param [Array<Hash<Object, Object>>] files Param documentation.
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @return [Hash<Object, Object>]
        def document_hash(files, state)
          {
            metadata: metadata_hash,
            files: files,
            summary: summary_hash(files, state)
          }
        end

        # Method documentation.
        #
        # @private
        # @return [Hash<Symbol, Object>]
        def metadata_hash
          {
            docscribe_version: Docscribe::VERSION,
            ruby_version: RUBY_VERSION
          }
        end

        # Method documentation.
        #
        # @private
        # @param [Array<Hash<Object, Object>>] files Param documentation.
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @return [Hash<Symbol, Integer>]
        def summary_hash(files, state)
          {
            offense_count: files.sum { |f| f[:offenses].size },
            target_file_count: files.size,
            inspected_file_count: inspected_count(state),
            error_count: state[:error_paths].size
          }
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @return [Array<Hash<Object, Object>>]
        def build_files(state)
          files = [] #: Array[Hash[untyped, untyped]]

          append_check_files(state, files) if state[:fail_paths].any? || state[:type_mismatch_paths].any?
          append_corrected_files(state, files) if state[:corrected_paths].any?
          append_error_files(state, files) if state[:error_paths].any?

          files
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @param [Array<Hash<Object, Object>>] files Param documentation.
        # @return [void]
        def append_check_files(state, files)
          state[:fail_paths].each do |path|
            files << file_entry(path, state[:fail_changes][path] || [])
          end

          state[:type_mismatch_paths].each do |path|
            files << file_entry(path, state[:type_mismatch_changes][path] || [], severity: 'warning')
          end
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @param [Array<Hash<Object, Object>>] files Param documentation.
        # @return [void]
        def append_corrected_files(state, files)
          state[:corrected_paths].each do |path|
            merge_or_append(files, path, state[:corrected_changes][path] || [])
          end
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @param [Array<Hash<Object, Object>>] files Param documentation.
        # @return [void]
        def append_error_files(state, files)
          state[:error_paths].each do |path|
            merge_or_append(files, path, [error_offense(state, path)])
          end
        end

        # Method documentation.
        #
        # @private
        # @param [Array<Hash<Object, Object>>] files Param documentation.
        # @param [String] path Param documentation.
        # @param [Array<Hash<Object, Object>>] offenses Param documentation.
        # @return [void]
        def merge_or_append(files, path, offenses)
          existing = files.find { |f| f[:path] == path }

          if existing
            existing[:offenses].concat(offenses)
          else
            files << { path: path, offenses: offenses }
          end
        end

        # Method documentation.
        #
        # @private
        # @param [String] path Param documentation.
        # @param [Array<Docscribe::CLI::Formatters::change>] changes Param documentation.
        # @param [String?] severity Param documentation.
        # @return [Hash<Symbol, Object>]
        def file_entry(path, changes, severity: nil)
          { path: path, offenses: build_offenses(changes, severity: severity) }
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @param [String] path Param documentation.
        # @return [Hash<Symbol, Object>]
        def error_offense(state, path)
          error_offense_hash(state[:error_messages][path] || 'Unknown error')
        end

        # Method documentation.
        #
        # @private
        # @param [String] message Param documentation.
        # @return [Hash<Symbol, Object>]
        def error_offense_hash(message)
          { severity: 'fatal', cop_name: 'Docscribe/ProcessingError', message: message,
            corrected: false, correctable: false, location: default_location }
        end

        # Method documentation.
        #
        # @private
        # @return [Hash<Symbol, Integer>]
        def default_location
          { start_line: 1, start_column: 1, last_line: 1, last_column: 1 }
        end

        # Method documentation.
        #
        # @private
        # @param [Array<Docscribe::CLI::Formatters::change>] changes Param documentation.
        # @param [String?] severity Param documentation.
        # @return [Array<Hash<Symbol, Object>>]
        def build_offenses(changes, severity: nil)
          changes.map { |change| build_offense(change, severity) }
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change Param documentation.
        # @param [String?] severity Param documentation.
        # @return [Hash<Symbol, Object>]
        def build_offense(change, severity)
          {
            severity: severity || SEVERITY_MAP[change[:type]] || 'convention',
            cop_name: COP_NAME_MAP[change[:type]] || cop_name_fallback(change),
            message: build_message(change),
            corrected: false,
            correctable: true,
            location: location_for(change)
          }
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change Param documentation.
        # @return [Hash<Symbol, Integer>]
        def location_for(change)
          line = change[:line] || 1
          { start_line: line, start_column: 1, last_line: line, last_column: 1 }
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change Param documentation.
        # @return [String]
        def cop_name_fallback(change)
          name = change[:type].to_s.tr('_', '_').capitalize
          "Docscribe/#{name}"
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::change] change Param documentation.
        # @return [String]
        def build_message(change)
          method = change[:method] ? " for #{change[:method]}" : ''
          line = change[:line] ? " at line #{change[:line]}" : ''

          return "unsorted tags#{line}" if change[:type] == :unsorted_tags

          msg = change[:message] || change[:type].to_s.tr('_', ' ')
          "#{msg}#{method}#{line}"
        end

        # Method documentation.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state Param documentation.
        # @return [Integer]
        def inspected_count(state)
          total = state[:checked_ok] + state[:checked_fail] + state[:type_mismatch_paths].size
          total = state[:corrected] if total.zero? && state[:corrected].positive?
          total + state[:error_paths].size
        end
      end
    end
  end
end
