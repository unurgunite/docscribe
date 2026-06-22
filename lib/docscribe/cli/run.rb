# frozen_string_literal: true

require 'pathname'

require 'docscribe/cli/config_builder'
require 'docscribe/cli/formatters'
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
        INITIAL_RUN_STATE = {
          changed: false,
          had_errors: false,
          checked_ok: 0,
          checked_fail: 0,
          corrected: 0,
          corrected_paths: [], #: Array[String]
          corrected_changes: {}, #: Hash[String, untyped]
          fail_paths: [], #: Array[String]
          fail_changes: {}, #: Hash[String, untyped]
          error_paths: [], #: Array[String]
          error_messages: {}, #: Hash[String, String]
          type_mismatch_paths: [], #: Array[String]
          type_mismatch_changes: {}, #: Hash[String, untyped]
          total: 0,
          processed: 0
        }.freeze
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
        # @param [Docscribe::CLI::Formatters::opts] options parsed CLI options
        # @param [Array<String>] argv remaining path arguments
        # @return [Integer] process exit code
        def run(options:, argv:)
          return run_via_server(options: options, argv: argv) if options[:server]

          conf = build_config(options)

          return run_stdin(options: options, conf: conf) if options[:mode] == :stdin

          paths = filtered_paths(argv, conf)
          return no_files_found unless paths.any?

          run_files(options: options, conf: conf, paths: paths)
        end

        # Run via the background server daemon.
        #
        # Each file is processed by the server, which keeps the Ruby runtime loaded
        # between requests.
        #
        # @param [Docscribe::CLI::Formatters::opts] options parsed CLI options
        # @param [Array<String>] argv remaining path arguments
        # @raise [RuntimeError]
        # @return [Integer] exit code
        # @return [Integer] if RuntimeError
        def run_via_server(options:, argv:)
          require 'docscribe/server'
          conf = build_config(options)
          config_path = conf.config_path
          ensure_server_running!(config_path: config_path)
          client = Docscribe::Server::Client.new(config_path: config_path)
          paths = filtered_paths(argv, conf)
          return no_files_found unless paths.any?

          run_files_via_server(client, paths, options)
        rescue RuntimeError => e
          warn e.message
          1
        end

        # Run files through the server client with progress tracking.
        #
        # @param [Docscribe::Server::Client] client server client
        # @param [Array<String>] paths file paths to process
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [Integer] exit code
        def run_files_via_server(client, paths, options)
          $stdout.sync = true
          state = initial_run_state
          state[:total] = paths.size
          pwd = Pathname.pwd
          paths.each do |path|
            process_one_file_via_server(client, path, options: options, pwd: pwd, state: state)
          end
          finalize_run(options, state)
          run_exit_code(options, state)
        end

        # Load and build the effective config from CLI options.
        #
        # @param [Docscribe::CLI::Formatters::opts] options parsed CLI options
        # @return [Docscribe::Config] effective config with plugins loaded
        def build_config(options)
          conf = Docscribe::Config.load(options[:config])
          conf = Docscribe::CLI::ConfigBuilder.build(conf, options)
          conf.load_plugins!
          conf
        end

        # Rewrite code from STDIN using the selected strategy and print the
        # result.
        #
        # @param [Docscribe::CLI::Formatters::opts] options parsed CLI options
        # @param [Docscribe::Config] conf effective config
        # @raise [StandardError]
        # @return [Integer] if StandardError
        # @return [Integer] if StandardError
        def run_stdin(options:, conf:)
          puts stdin_rewrite_result(options, conf)[:output]
          0
        rescue StandardError => e
          warn "Docscribe: Error processing stdin: #{e.class}: #{e.message}"
          1
        end

        # Rewrite STDIN input and return the result report.
        #
        # @param [Docscribe::CLI::Formatters::opts] options parsed CLI options
        # @param [Docscribe::Config] conf effective config
        # @return [Hash<Symbol, Object>] rewrite result with :output key
        def stdin_rewrite_result(options, conf)
          Docscribe::InlineRewriter.rewrite_with_report(
            $stdin.read,
            strategy: options[:strategy],
            config: conf,
            core_rbs_provider: core_rbs_provider_for(conf),
            file: '(stdin)'
          )
        end

        # Return the core RBS provider from the config if available.
        #
        # @param [Docscribe::Config] conf effective config
        # @return [Docscribe::Types::RBS::Provider, nil] core RBS provider or nil
        def core_rbs_provider_for(conf)
          conf.respond_to?(:core_rbs_provider) ? conf.core_rbs_provider : nil
        end

        # Expand CLI path arguments and filter through config file patterns.
        #
        # @param [Array<String>] argv CLI path arguments
        # @param [Docscribe::Config] conf effective config
        # @return [Array<String>] filtered Ruby file paths
        def filtered_paths(argv, conf)
          expand_paths(argv).select { |path| conf.process_file?(path) }
        end

        # Warn and return exit code when no matching files were found.
        #
        # @return [Integer] exit code 2
        def no_files_found
          warn 'No files found. Pass files or directories (e.g. `docscribe lib`).'
          2
        end

        # Ensure the server daemon is running, auto-starting if necessary.
        #
        # @param [String?] config_path
        # @return [void]
        def ensure_server_running!(config_path: nil)
          return if Docscribe::Server.running?(config_path)

          warn 'Docscribe: starting server...'
          pid = fork do
            daemon = Docscribe::Server::Daemon.new(config_path: config_path)
            daemon.start
          end
          Process.detach(pid)
          wait_for_server(config_path: config_path)
        end

        # Wait for the server to become ready.
        #
        # @param [Integer] timeout max seconds to wait
        # @param [String?] config_path
        # @raise [StandardError]
        # @return [void]
        def wait_for_server(timeout: 5, config_path: nil)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          loop do
            return if Docscribe::Server.running?(config_path)

            if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              raise 'Docscribe: server failed to start'
            end

            sleep 0.1
          end
        end

        # Process a single file via the server client.
        #
        # @param [Docscribe::Server::Client] client server client
        # @param [String] path file path
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Pathname] pwd current working directory
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def process_one_file_via_server(client, path, options:, pwd:, state:)
          display_path = display_path_for(path, pwd: pwd)
          report_progress(state, options, display_path)
          response = send_server_request(client, path, options)
          return server_error(path, state, 'Server unreachable') unless response
          return server_error(path, state, response['error']['message']) if response['error']

          result = response['result']
          file_changes = (result['changes'] || []).map { |c| symbolize_change(c) }
          dispatch_server_result(result, file_changes, path,
                                 display_path: display_path, options: options, state: state)
        end

        # Send a request to the server for a file.
        #
        # @param [Docscribe::Server::Client] client server client
        # @param [String] path file path
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [Hash<String, Object>, nil] server response
        def send_server_request(client, path, options)
          method_name = options[:mode] == :write ? 'fix' : 'check'
          strategy = options[:strategy].to_s
          client.send(method_name, file: path, strategy: strategy)
        end

        # Record a server error in the shared state and print an indicator.
        #
        # @param [String] path file path
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [String] message error message
        # @return [void]
        def server_error(path, state, message)
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = message
          $stderr.print('E')
        end

        # Dispatch the server result to check or write handler.
        #
        # @param [Hash<String, Object>] result server result with :changed and :changes keys
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes change records
        # @param [String] path file path
        # @param [Object] ctx context hash with :display_path, :options, :state keys
        # @return [void]
        def dispatch_server_result(result, file_changes, path, **ctx)
          if ctx[:options][:mode] == :check
            handle_via_server_check(path, file_changes: file_changes,
                                          display_path: ctx[:display_path],
                                          options: ctx[:options], state: ctx[:state])
          else
            write_server_result(result, file_changes, display_path: ctx[:display_path],
                                                      options: ctx[:options], state: ctx[:state])
          end
        end

        # Handle a server write-mode result.
        #
        # @param [Hash<String, Object>] result server result with :changed key
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes change records
        # @param [String] display_path path shown in CLI output
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def write_server_result(result, file_changes, display_path:, options:, state:)
          if result['changed']
            state[:corrected] += 1
            state[:corrected_paths] << display_path
            state[:corrected_changes][display_path] = file_changes
            log_check_verdict('CHANGED', display_path, options)
          else
            log_check_verdict('OK', display_path, options)
          end
        end

        # Handle a check result from the server.
        #
        # @param [String] path file path
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes change records from server
        # @param [String] display_path path shown in CLI output
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def handle_via_server_check(path, file_changes:, display_path:, options:, state:)
          if file_changes.empty?
            state[:checked_ok] += 1
            return log_check_verdict('OK', display_path, options)
          end

          report_check_failure(display_path, file_changes, options)
          update_check_failure_state(path, file_changes, state)
        end

        # Report a check failure with verbose or compact output.
        #
        # @param [String] display_path path shown in CLI output
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes change records from server
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def report_check_failure(display_path, file_changes, options)
          if options[:verbose]
            warn("FAIL #{display_path}")
            print_check_explanations(file_changes)
          else
            $stderr.print('F')
          end
        end

        # Update shared state after a check failure.
        #
        # @param [String] path file path
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes change records from server
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def update_check_failure_state(path, file_changes, state)
          state[:checked_fail] += 1
          state[:changed] = true
          state[:fail_paths] << path
          state[:fail_changes][path] = file_changes
        end

        # Convert server response change (string keys) to formatter-compatible
        # change (symbol keys).
        #
        # @param [Hash<String, Object>] change change record from server
        # @return [Docscribe::CLI::Formatters::change]
        def symbolize_change(change)
          {
            type: change['type'].to_sym,
            file: change['file'],
            line: change['line'],
            method: change['method'],
            message: change['message']
          }
        end

        # Expand CLI path arguments into a sorted list of Ruby files.
        #
        # Directories are expanded recursively to `**/*.rb`.
        # If no arguments are provided, the current directory is used.
        #
        # @param [Array<String>] args file and/or directory arguments
        # @return [Array<String>] unique sorted Ruby file paths
        def expand_paths(args)
          files = [] #: Array[String]
          args = ['.'] if args.empty?

          args.each do |path|
            append_expanded_path(files, path)
          end

          files.uniq.sort
        end

        # Append a file or recursively expand a directory into the files array.
        #
        # @param [Array<String>] files mutable file path accumulator
        # @param [String] path file or directory path to expand
        # @return [void]
        def append_expanded_path(files, path)
          if File.directory?(path)
            files.concat(Dir.glob(File.join(path, '**', '*.rb')))
          elsif File.file?(path)
            files << path
          else
            warn "Skipping missing path: #{path}"
          end
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
        # @param [Docscribe::CLI::Formatters::opts] options parsed CLI options
        # @param [Docscribe::Config] conf effective config
        # @param [Array<String>] paths Ruby file paths to process
        # @return [Integer] process exit code
        def run_files(options:, conf:, paths:)
          $stdout.sync = true

          state = initial_run_state
          state[:total] = paths.size
          pwd = Pathname.pwd

          paths.each do |path|
            process_one_file(path, options: options, conf: conf, pwd: pwd, state: state)
          end

          finalize_run(options, state)

          run_exit_code(options, state)
        end

        private

        # Print the check or write summary at the end of a run.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def finalize_run(options, state)
          formatter = Formatters.for(options[:format])

          if options[:mode] == :check
            formatter.format_check_summary(state: state, options: options)
          elsif options[:mode] == :write
            formatter.format_write_summary(state: state, options: options)
          end
        end

        # Determine the process exit code based on run state and mode.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [Integer] exit code: 0 = OK, 1 = findings, 2 = error
        def run_exit_code(options, state)
          return 2 if state[:had_errors]
          return 1 if options[:mode] == :check && state[:changed]

          0
        end

        # Initialize the shared state hash used throughout a run.
        #
        # @private
        # @return [Docscribe::CLI::Formatters::state] initial state with counters and tracking arrays
        def initial_run_state
          Marshal.load(Marshal.dump(INITIAL_RUN_STATE))
        end

        # Process a single file: read, rewrite, and dispatch to check/write handler.
        #
        # @private
        # @param [String] path file path
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::Config] conf configuration
        # @param [Pathname] pwd current working directory
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def process_one_file(path, options:, conf:, pwd:, state:)
          display_path = display_path_for(path, pwd: pwd)
          report_progress(state, options, display_path)

          src = read_source_for_path(path, display_path: display_path, options: options, state: state)
          return unless src

          ctx = { conf: conf, display_path: display_path, options: options, state: state }
          result = rewrite_result_for_path(path, src: src, ctx: ctx)
          return unless result

          dispatch_file_result(path, src: src, out: result[:output], file_changes: result[:changes] || [],
                                     display_path: display_path, options: options, state: state)
        end

        # Print progress indicator to stderr when --progress is active.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [String] display_path path to display
        # @return [void]
        def report_progress(state, options, display_path)
          state[:processed] += 1
          return unless options[:progress]

          warn "[#{state[:processed]}/#{state[:total]}] #{display_path}"
        end

        # Dispatch the rewrite result to the check or write handler based on mode.
        #
        # @private
        # @param [String] path file path
        # @param [String] src original source code
        # @param [String] out rewritten source code
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @param [Object] ctx context hash with :options, :state, :display_path, :conf
        # @return [void]
        def dispatch_file_result(path, src:, out:, file_changes:, **ctx)
          if ctx[:options][:mode] == :check
            handle_check_result(path, src: src, out: out, file_changes: file_changes, **ctx)
          elsif ctx[:options][:mode] == :write
            handle_write_result(path, src: src, out: out, file_changes: file_changes, **ctx)
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
        # @return [String] if StandardError
        # @return [Object] if StandardError
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
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @raise [StandardError]
        # @return [String, nil] if StandardError
        # @return [nil] if StandardError
        def read_source_for_path(path, display_path:, options:, state:)
          File.read(path)
        rescue StandardError => e
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{e.class}: #{e.message}"
          options[:verbose] ? warn("ERR #{display_path}: #{state[:error_messages][path]}") : $stderr.print('E')
          nil
        end

        # Rewrite the source file using InlineRewriter and handle rewrite errors.
        #
        # @private
        # @param [String] path file path
        # @param [String] src source code
        # @param [Hash<Symbol, Object>] ctx context hash with :conf, :display_path, :options, :state keys
        # @raise [StandardError]
        # @return [Hash<Symbol, Object>, nil] if StandardError
        # @return [nil] if StandardError
        def rewrite_result_for_path(path, src:, ctx:)
          conf = ctx[:conf]

          core_rbs_provider =
            conf.respond_to?(:core_rbs_provider) ? conf.core_rbs_provider : nil

          Docscribe::InlineRewriter.rewrite_with_report(
            src, strategy: ctx[:options][:strategy], config: conf, core_rbs_provider: core_rbs_provider, file: path
          )
        rescue StandardError => e
          record_rewrite_error(path, e, ctx)
          nil
        end

        # Record a rewrite error in the shared state and print an error indicator.
        #
        # @private
        # @param [String] path file path that caused the error
        # @param [StandardError] error the exception raised during rewriting
        # @param [Hash<Symbol, Object>] ctx context hash with :state, :options, :display_path
        # @return [void]
        def record_rewrite_error(path, error, ctx)
          state = ctx[:state]

          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{error.class}: #{error.message}"

          if ctx[:options][:verbose]
            warn "ERR #{ctx[:display_path]}: #{state[:error_messages][path]}"
          else
            $stderr.print('E')
          end
        end

        # Handle the result of an inspect (check) run.
        #
        # @private
        # @param [String] path file path
        # @param [String] src original source code
        # @param [String] out rewritten source code
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @param [Object] ctx context hash with :display_path, :options, :state keys
        # @return [void]
        def handle_check_result(path, src:, out:, file_changes:, **ctx)
          type_mismatches = type_mismatch_changes(file_changes)
          has_real_changes = file_changes.any? { |c| !%i[updated_param updated_return].include?(c[:type]) }

          if out == src && !has_real_changes
            handle_check_no_changes(path, type_mismatches: type_mismatches, display_path: ctx[:display_path],
                                          options: ctx[:options], state: ctx[:state])
            return
          end

          handle_check_failed(path, file_changes: file_changes, display_path: ctx[:display_path],
                                    options: ctx[:options], state: ctx[:state])
        end

        # Extract type mismatch changes from file_changes.
        #
        # @private
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @return [Array<Docscribe::CLI::Formatters::change>]
        def type_mismatch_changes(file_changes)
          file_changes.select { |c| %i[updated_param updated_return].include?(c[:type]) }
        end

        # Handle check result when there are no real changes.
        #
        # @private
        # @param [String] path file path
        # @param [Array<Docscribe::CLI::Formatters::change>] type_mismatches type mismatch changes to record
        # @param [String] display_path path shown in CLI output
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
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
        # With --verbose, prints the per-file verdict and all change reasons.
        #
        # @private
        # @param [String] path file path
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @param [String] display_path path shown in CLI output
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def handle_check_failed(path, file_changes:, display_path:, options:, state:)
          if options[:verbose]
            warn("FAIL #{display_path}")
            print_check_explanations(file_changes)
          else
            $stderr.print('F')
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
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @param [Object] ctx context hash with :display_path, :options, :state keys
        # @raise [StandardError]
        # @return [void] if StandardError
        # @return [Object] if StandardError
        def handle_write_result(path, src:, out:, file_changes:, **ctx)
          return log_check_verdict('OK', ctx[:display_path], ctx[:options]) if out == src

          apply_correction(path, out, file_changes, ctx)
        rescue StandardError => e
          record_write_error(path, e, display_path: ctx[:display_path], options: ctx[:options], state: ctx[:state])
        end

        # Apply a file correction — write to disk, log, and update state.
        #
        # @private
        # @param [String] path file path
        # @param [String] out rewritten source code
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @param [Hash<Symbol, Object>] ctx context hash with :display_path, :options, :state keys
        # @return [void]
        def apply_correction(path, out, file_changes, ctx)
          File.write(path, out)
          log_write_verdict('CHANGED', ctx[:display_path], file_changes, ctx[:options])
          update_correction_state(ctx[:state], ctx[:display_path], file_changes)
        end

        # Update the shared state after a successful correction.
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [String] display_path path shown in CLI output
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @return [void]
        def update_correction_state(state, display_path, file_changes)
          state[:corrected] += 1
          state[:corrected_paths] << display_path
          state[:corrected_changes][display_path] = file_changes
        end

        # Log a write-mode verdict.
        #
        # @private
        # @param [String] verdict verdict string to display
        # @param [String] display_path path shown in CLI output
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def log_write_verdict(verdict, display_path, file_changes, options)
          if options[:verbose]
            warn("#{verdict} #{display_path}")
            print_check_explanations(file_changes)
          else
            $stderr.print('C')
          end
        end

        # Print explanations for file changes.
        #
        # Callers are responsible for gating on --verbose / --explain.
        #
        # @private
        # @param [Array<Docscribe::CLI::Formatters::change>] file_changes structured change records
        # @return [void]
        def print_check_explanations(file_changes)
          file_changes.each do |change|
            warn("  - #{format_change_reason(change)}")
          end
        end

        # Record a write error in state.
        #
        # @private
        # @param [String] path file path
        # @param [StandardError] error the exception raised during file write
        # @param [String] display_path path shown in CLI output
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
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
        # @param [String] verdict verdict string to display
        # @param [String] display_path path shown in CLI output
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def log_check_verdict(verdict, display_path, options)
          if options[:verbose]
            warn("#{verdict} #{display_path}")
          else
            $stderr.print(if verdict == 'FAIL'
                            'F'
                          else
                            verdict == 'MT' ? 'M' : '.'
                          end)
          end
        end

        # Print the check-mode summary (fail paths, then status line).
        #
        # @private
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def print_check_summary(state:, options:)
          puts
          print_fail_paths(state, options)
          print_check_status_line(state)
          print_type_mismatch_paths(state, options)
          print_error_paths(state)
        end

        public

        # Print fail paths from check summary (stdout).
        #
        # Skips explanations when --verbose showed them inline per-file.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def print_fail_paths(state, options)
          state[:fail_paths].each do |p|
            puts "Would update: #{p}"

            next if options[:verbose] || options[:quiet]

            Array(state[:fail_changes][p]).each do |change|
              puts "  - #{format_change_reason(change)}"
            end
          end
        end

        # Print the check-mode status line.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def print_check_status_line(state)
          checked_error = state[:error_paths].size
          type_mismatch_count = state[:type_mismatch_paths].size

          if all_fine?(state, checked_error, type_mismatch_count)
            puts "Docscribe: OK (#{state[:checked_ok]} files checked)"
          elsif mismatch_only?(state, checked_error)
            puts "Docscribe: OK (#{state[:checked_ok]} files checked, #{type_mismatch_count} with type mismatches)"
          else
            puts build_failure_line(state, type_mismatch_count, checked_error)
          end
        end

        # Whether no failures, errors, or type mismatches occurred.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Integer] checked_error number of files with errors
        # @param [Integer] type_mismatch_count number of files with type mismatches
        # @return [Boolean]
        def all_fine?(state, checked_error, type_mismatch_count)
          state[:checked_fail].zero? && checked_error.zero? && type_mismatch_count.zero?
        end

        # Whether type mismatches exist but no failures or errors.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Integer] checked_error number of files with errors
        # @return [Boolean]
        def mismatch_only?(state, checked_error)
          state[:checked_fail].zero? && checked_error.zero?
        end

        # Build the human-readable failure summary line for check output.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Integer] type_mismatch_count number of files with type mismatches
        # @param [Integer] checked_error number of files with errors
        # @return [String]
        def build_failure_line(state, type_mismatch_count, checked_error)
          parts = ["#{state[:checked_fail]} need updates"]
          parts << "#{type_mismatch_count} type mismatches" if type_mismatch_count.positive?
          parts << "#{checked_error} errors"
          parts << "#{state[:checked_ok]} ok"
          "Docscribe: FAILED (#{parts.join(', ')})"
        end

        # Print type mismatch paths from check summary.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def print_type_mismatch_paths(state, options)
          return if options[:quiet]
          return unless options[:verbose] || options[:explain]

          state[:type_mismatch_paths].each do |p|
            warn "Type mismatches: #{p}"
            Array(state[:type_mismatch_changes][p]).each do |change|
              warn "  - #{format_change_reason(change)}"
            end
          end
        end

        # Print the write-mode summary (files corrected, errors).
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def print_write_summary(state:, options:)
          puts
          puts "Docscribe: updated #{state[:corrected]} file(s)" if state[:corrected].positive?
          print_corrected_paths(state, options)

          return unless state[:had_errors]

          warn "Docscribe: #{state[:error_paths].size} file(s) had errors"
          print_error_paths(state)
        end

        # Print corrected paths from write-mode summary (stdout).
        #
        # Skips explanations when --verbose showed them inline per-file.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @param [Docscribe::CLI::Formatters::opts] options CLI options
        # @return [void]
        def print_corrected_paths(state, options)
          state[:corrected_paths].each do |p|
            puts "Updated: #{p}"

            next if options[:verbose] || options[:quiet]

            Array(state[:corrected_changes][p]).each do |change|
              puts "  - #{format_change_reason(change)}"
            end
          end
        end

        # Format a structured change record into human-readable CLI output.
        #
        # @param [Docscribe::CLI::Formatters::change] change structured change produced by the inline rewriter
        # @return [String] human-readable explanation line
        def format_change_reason(change)
          line = change_line_suffix(change)
          method = change_method_suffix(change)

          return "unsorted tags#{line}" if change[:type] == :unsorted_tags
          return "#{change[:message]}#{method}#{line}" if direct_message_change?(change)

          "#{change[:message] || change[:type].to_s.tr('_', ' ')}#{method}#{line}"
        end

        # Format the line number suffix for a change reason string.
        #
        # @param [Docscribe::CLI::Formatters::change] change structured change record
        # @return [String] " at line N" or empty
        def change_line_suffix(change)
          change[:line] ? " at line #{change[:line]}" : ''
        end

        # Format the method name suffix for a change reason string.
        #
        # @param [Docscribe::CLI::Formatters::change] change structured change record
        # @return [String] " for method_name" or empty
        def change_method_suffix(change)
          change[:method] ? " for #{change[:method]}" : ''
        end

        # Whether a change type uses its own :message field directly as the reason.
        #
        # @param [Docscribe::CLI::Formatters::change] change structured change record
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

        # Print error paths from check summary.
        #
        # @param [Docscribe::CLI::Formatters::state] state shared processing state
        # @return [void]
        def print_error_paths(state)
          return if state[:error_paths].empty?

          warn ''
          state[:error_paths].each do |p|
            warn "Error processing: #{p}"
            warn "  #{state[:error_messages][p]}" if state[:error_messages][p]
          end
        end
      end
    end
  end
end
