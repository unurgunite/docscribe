# frozen_string_literal: true

require 'pathname'

require 'docscribe/cli/config_builder'
require 'docscribe/inline_rewriter'

module Docscribe
  module CLI
    # Execute Docscribe from parsed CLI options.
    #
    # This module handles:
    # - config loading and CLI overrides
    # - stdin mode
    # - file expansion / filtering
    # - inspect vs write behavior
    # - process exit status
    module Run
      class << self
        # Run Docscribe for files or STDIN using the selected mode and strategy.
        #
        # Modes:
        # - :check => inspect what the selected strategy would change
        # - :write => apply the selected strategy in place
        # - :stdin => rewrite STDIN and print to STDOUT
        #
        # Strategies:
        # - :safe       => merge/add/normalize non-destructively
        # - :aggressive => rebuild existing doc blocks
        #
        # @param [Hash] options parsed CLI options
        # @param [Array<String>] argv remaining path arguments
        # @return [Integer] process exit code
        def run(options:, argv:)
          conf = Docscribe::Config.load(options[:config])
          conf = Docscribe::CLI::ConfigBuilder.build(conf, options)
          conf.load_plugins!

          return run_stdin(options: options, conf: conf) if options[:mode] == :stdin

          paths = expand_paths(argv)
          paths = paths.select { |p| conf.process_file?(p) }

          if paths.empty?
            warn 'No files found. Pass files or directories (e.g. `docscribe lib`).'
            return 1
          end

          run_files(options: options, conf: conf, paths: paths)
        end

        # Rewrite code from STDIN using the selected strategy and print the
        # result.
        #
        # @param [Hash] options parsed CLI options
        # @param [Docscribe::Config] conf effective config
        # @raise [StandardError]
        # @return [Integer] process exit code
        def run_stdin(options:, conf:)
          code = $stdin.read
          result = Docscribe::InlineRewriter.rewrite_with_report(
            code,
            strategy: options[:strategy],
            config: conf,
            core_rbs_provider: conf.respond_to?(:core_rbs_provider) ? conf.core_rbs_provider : nil,
            file: '(stdin)'
          )
          puts result[:output]
          0
        rescue StandardError => e
          warn "Docscribe: Error processing stdin: #{e.class}: #{e.message}"
          1
        end

        # Expand CLI path arguments into a sorted list of Ruby files.
        #
        # Directories are expanded recursively to `**/*.rb`.
        # If no arguments are provided, the current directory is used.
        #
        # @param [Array<String>] args file and/or directory arguments
        # @return [Array<String>] unique sorted Ruby file paths
        def expand_paths(args)
          files = []
          args = ['.'] if args.empty?

          args.each do |path|
            if File.directory?(path)
              files.concat(Dir.glob(File.join(path, '**', '*.rb')))
            elsif File.file?(path)
              files << path
            else
              warn "Skipping missing path: #{path}"
            end
          end

          files.uniq.sort
        end

        # Process file paths in inspect or write mode.
        #
        # In inspect mode:
        # - prints progress/status
        # - exits non-zero if any file would change or if any errors occurred
        #
        # In write mode:
        # - rewrites changed files in place
        # - exits non-zero only if errors occurred
        #
        # @param [Hash] options parsed CLI options
        # @param [Docscribe::Config] conf effective config
        # @param [Array<String>] paths Ruby file paths to process
        # @return [Integer] process exit code
        def run_files(options:, conf:, paths:)
          $stdout.sync = true

          state = initial_run_state
          pwd = Pathname.pwd

          paths.each do |path|
            process_one_file(path, options: options, conf: conf, pwd: pwd, state: state)
          end

          if options[:mode] == :check
            print_check_summary(state: state, options: options)
          elsif options[:mode] == :write
            print_write_summary(state: state)
          end

          return 1 if state[:had_errors]
          return 1 if options[:mode] == :check && state[:changed]

          0
        end

        private

        # Initialize the shared state hash used throughout a run.
        #
        # @private
        # @return [Hash] initial state with counters and tracking arrays
        def initial_run_state
          {
            changed: false,
            had_errors: false,
            checked_ok: 0,
            checked_fail: 0,
            corrected: 0,
            fail_paths: [],
            fail_changes: {},
            error_paths: [],
            error_messages: {},
            type_mismatch_paths: [],
            type_mismatch_changes: {}
          }
        end

        # Process a single file: read, rewrite, and dispatch to check/write handler.
        #
        # @private
        # @param [String] path file path
        # @param [Hash] options CLI options
        # @param [Docscribe::Config] conf configuration
        # @param [Pathname] pwd current working directory
        # @param [Hash] state shared processing state
        # @return [void]
        def process_one_file(path, options:, conf:, pwd:, state:)
          display_path = display_path_for(path, pwd: pwd)

          src = read_source_for_path(path, display_path: display_path, options: options, state: state)
          return unless src

          result = rewrite_result_for_path(path, src: src, conf: conf, display_path: display_path, options: options,
                                                 state: state)
          return unless result

          out = result[:output]
          file_changes = result[:changes] || []

          if options[:mode] == :check
            handle_check_result(
              path,
              src: src,
              out: out,
              file_changes: file_changes,
              display_path: display_path,
              options: options,
              state: state
            )
          elsif options[:mode] == :write
            handle_write_result(
              path,
              src: src,
              out: out,
              file_changes: file_changes,
              display_path: display_path,
              options: options,
              state: state
            )
          end
        end

        # Prefer a relative display path when the file is under the current working directory.
        #
        # Falls back to basename for files outside the project root or when relative path
        # computation fails.
        #
        # @private
        # @param [String] path file path to display
        # @param [Pathname] pwd current working directory
        # @raise [StandardError]
        # @return [String] path shown in CLI output
        def display_path_for(path, pwd:)
          abs = Pathname.new(path).expand_path

          pwd_str = pwd.to_s
          abs_str = abs.to_s
          return abs.relative_path_from(pwd).to_s if abs_str.start_with?(pwd_str + File::SEPARATOR)

          File.basename(abs_str)
        rescue StandardError
          File.basename(path.to_s)
        end

        # Read the source file and handle read errors.
        #
        # @private
        # @param [String] path file path to read
        # @param [String] display_path path shown in CLI output
        # @param [Hash] options CLI options
        # @param [Hash] state shared processing state
        # @raise [StandardError]
        # @return [String, nil] file contents or nil on error
        def read_source_for_path(path, display_path:, options:, state:)
          File.read(path)
        rescue StandardError => e
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{e.class}: #{e.message}"
          options[:verbose] ? warn("ERR #{display_path}: #{state[:error_messages][path]}") : print('E')
          nil
        end

        # Rewrite the source file using InlineRewriter and handle rewrite errors.
        #
        # @private
        # @param [String] path file path
        # @param [String] src source code
        # @param [Docscribe::Config] conf configuration
        # @param [String] display_path path shown in CLI output
        # @param [Hash] options CLI options
        # @param [Hash] state shared processing state
        # @raise [StandardError]
        # @return [Hash, nil] rewrite result or nil on error
        def rewrite_result_for_path(path, src:, conf:, display_path:, options:, state:)
          core_rbs_provider = conf.respond_to?(:core_rbs_provider) ? conf.core_rbs_provider : nil
          Docscribe::InlineRewriter.rewrite_with_report(
            src,
            strategy: options[:strategy],
            config: conf,
            core_rbs_provider: core_rbs_provider,
            file: path
          )
        rescue StandardError => e
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{e.class}: #{e.message}"
          options[:verbose] ? warn("ERR #{display_path}: #{state[:error_messages][path]}") : print('E')
          nil
        end

        # Handle the result of an inspect (check) run.
        #
        # @private
        # @param [String] path file path
        # @param [String] src original source code
        # @param [String] out rewritten source code
        # @param [Array<Hash>] file_changes structured change records
        # @param [String] display_path path shown in CLI output
        # @param [Hash] options CLI options
        # @param [Hash] state shared processing state
        # @return [void]
        def handle_check_result(path, src:, out:, file_changes:, display_path:, options:, state:)
          type_mismatches = type_mismatch_changes(file_changes)
          has_real_changes = file_changes.any? { |c| !%i[updated_param updated_return].include?(c[:type]) }

          if out == src && !has_real_changes
            handle_check_no_changes(path, type_mismatches: type_mismatches, display_path: display_path,
                                          options: options, state: state)
            return
          end

          handle_check_failed(path, file_changes: file_changes, display_path: display_path,
                                    options: options, state: state)
        end

        # Extract type mismatch changes from file_changes.
        #
        # @private
        # @param [Array<Hash>] file_changes
        # @return [Array<Hash>]
        def type_mismatch_changes(file_changes)
          file_changes.select { |c| %i[updated_param updated_return].include?(c[:type]) }
        end

        # Handle check result when there are no real changes.
        #
        # @private
        # @param [String] path
        # @param [Array<Hash>] type_mismatches
        # @param [String] display_path
        # @param [Hash] options
        # @param [Hash] state
        # @return [void]
        def handle_check_no_changes(path, type_mismatches:, display_path:, options:, state:)
          if type_mismatches.any?
            state[:type_mismatch_paths] << path
            state[:type_mismatch_changes][path] = type_mismatches
            log_check_verdict('MT', display_path, options)
          else
            state[:checked_ok] += 1
            log_check_verdict('OK', display_path, options)
          end
        end

        # Handle a failed check (file needs updates).
        #
        # @private
        # @param [String] path
        # @param [Array<Hash>] file_changes
        # @param [String] display_path
        # @param [Hash] options
        # @param [Hash] state
        # @return [void]
        def handle_check_failed(path, file_changes:, display_path:, options:, state:)
          if options[:verbose]
            puts("FAIL #{display_path}")
            print_check_explanations(file_changes, options)
          else
            print('F')
          end

          state[:checked_fail] += 1
          state[:changed] = true
          state[:fail_paths] << path
          state[:fail_changes][path] = file_changes
        end

        # Handle the result of an autocorrect (write) run.
        #
        # @private
        # @param [String] path file path
        # @param [String] src original source code
        # @param [String] out rewritten source code
        # @param [Array<Hash>] file_changes structured change records
        # @param [String] display_path path shown in CLI output
        # @param [Hash] options CLI options
        # @param [Hash] state shared processing state
        # @raise [StandardError]
        # @return [void]
        def handle_write_result(path, src:, out:, file_changes:, display_path:, options:, state:)
          if out == src
            log_check_verdict('OK', display_path, options)
            return
          end

          File.write(path, out)
          log_write_verdict('CHANGED', display_path, file_changes, options)
          state[:corrected] += 1
        rescue StandardError => e
          record_write_error(path, e, display_path: display_path, options: options, state: state)
        end

        # Log a write-mode verdict.
        #
        # @private
        # @param [String] verdict
        # @param [String] display_path
        # @param [Array<Hash>] file_changes
        # @param [Hash] options
        # @return [void]
        def log_write_verdict(verdict, display_path, file_changes, options)
          if options[:verbose]
            puts("#{verdict} #{display_path}")
            print_check_explanations(file_changes, options)
          else
            print('C')
          end
        end

        # Print explanations for file changes.
        #
        # @private
        # @param [Array<Hash>] file_changes
        # @param [Hash] options
        # @return [void]
        def print_check_explanations(file_changes, options)
          return unless options[:explain]

          file_changes.each do |change|
            puts("  - #{format_change_reason(change)}")
          end
        end

        # Record a write error in state.
        #
        # @private
        # @param [String] path
        # @param [StandardError] e
        # @param [String] display_path
        # @param [Hash] options
        # @param [Hash] state
        # @param [Object] error Param documentation.
        # @return [void]
        def record_write_error(path, error, display_path:, options:, state:)
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{error.class}: #{error.message}"
          log_check_verdict('ERR', display_path, options)
        end

        # Log a per-file check verdict.
        #
        # @private
        # @param [String] verdict
        # @param [String] display_path
        # @param [Hash] options
        # @return [void]
        def log_check_verdict(verdict, display_path, options)
          if options[:verbose]
            puts("#{verdict} #{display_path}")
          else
            print(if verdict == 'FAIL'
                    'F'
                  else
                    verdict == 'MT' ? 'M' : '.'
                  end)
          end
        end

        # Print the check-mode summary (files OK / need updates / errors).
        #
        # @private
        # @param [Hash] state shared processing state
        # @param [Hash] options CLI options
        # @return [void]
        def print_check_summary(state:, options:)
          puts
          print_check_status_line(state)
          print_fail_paths(state, options)
          print_type_mismatch_paths(state, options)
          print_error_paths(state)
        end

        # Print the check-mode status line.
        #
        # @private
        # @param [Hash] state
        # @return [void]
        def print_check_status_line(state)
          checked_error = state[:error_paths].size
          type_mismatch_count = state[:type_mismatch_paths].size

          if state[:checked_fail].zero? && checked_error.zero? && type_mismatch_count.zero?
            puts "Docscribe: OK (#{state[:checked_ok]} files checked)"
            return
          end

          if state[:checked_fail].zero? && checked_error.zero?
            puts "Docscribe: OK (#{state[:checked_ok]} files checked, #{type_mismatch_count} with type mismatches)"
          else
            parts = ["#{state[:checked_fail]} need updates"]
            parts << "#{type_mismatch_count} type mismatches" if type_mismatch_count.positive?
            parts << "#{checked_error} errors"
            parts << "#{state[:checked_ok]} ok"
            puts "Docscribe: FAILED (#{parts.join(', ')})"
          end
        end

        # Print fail paths from check summary.
        #
        # @private
        # @param [Hash] state
        # @param [Hash] options
        # @return [void]
        def print_fail_paths(state, options)
          state[:fail_paths].each do |p|
            warn "Would update docs: #{p}"
            next unless options[:explain] && !options[:verbose]

            Array(state[:fail_changes][p]).each do |change|
              warn "  - #{format_change_reason(change)}"
            end
          end
        end

        # Print type mismatch paths from check summary.
        #
        # @private
        # @param [Hash] state
        # @param [Hash] options
        # @return [void]
        def print_type_mismatch_paths(state, options)
          return unless options[:verbose] || options[:explain]

          state[:type_mismatch_paths].each do |p|
            warn "Type mismatches: #{p}"
            Array(state[:type_mismatch_changes][p]).each do |change|
              warn "  - #{format_change_reason(change)}"
            end
          end
        end

        # Print error paths from check summary.
        #
        # @private
        # @param [Hash] state
        # @return [void]
        def print_error_paths(state)
          state[:error_paths].each do |p|
            warn "Error processing: #{p}"
            warn "  #{state[:error_messages][p]}" if state[:error_messages][p]
          end
        end

        # Format a structured change record into human-readable CLI output.
        #
        # @private
        # @param [Hash] change structured change produced by the inline rewriter
        # @return [String] human-readable explanation line
        def format_change_reason(change)
          line = change[:line] ? " at line #{change[:line]}" : ''
          method = change[:method] ? " for #{change[:method]}" : ''

          case change[:type]
          when :unsorted_tags
            "unsorted tags#{line}"
          when :missing_param, :missing_return, :missing_raise, :missing_visibility, :missing_module_function_note,
            :insert_full_doc_block
            "#{change[:message]}#{method}#{line}"
          else
            "#{change[:message] || change[:type].to_s.tr('_', ' ')}#{method}#{line}"
          end
        end

        # Print the write-mode summary (files corrected, errors).
        #
        # @private
        # @param [Hash] state shared processing state
        # @return [void]
        def print_write_summary(state:)
          puts
          puts "Docscribe: updated #{state[:corrected]} file(s)" if state[:corrected].positive?

          return unless state[:had_errors]

          warn "Docscribe: #{state[:error_paths].size} file(s) had errors"
          state[:error_paths].each do |p|
            warn "Error processing: #{p}"
            warn "  #{state[:error_messages][p]}" if state[:error_messages][p]
          end
        end
      end
    end
  end
end
