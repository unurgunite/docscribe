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

        # Method documentation.
        #
        # @private
        # @return [Hash]
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
            error_messages: {}
          }
        end

        # Method documentation.
        #
        # @private
        # @param [Object] path Param documentation.
        # @param [Hash] options Param documentation.
        # @param [Object] conf Param documentation.
        # @param [Object] pwd Param documentation.
        # @param [Object] state Param documentation.
        # @return [Object]
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

        # Method documentation.
        #
        # @private
        # @param [Object] path Param documentation.
        # @param [Object] display_path Param documentation.
        # @param [Hash] options Param documentation.
        # @param [Object] state Param documentation.
        # @raise [StandardError]
        # @return [Object]
        # @return [nil] if StandardError
        def read_source_for_path(path, display_path:, options:, state:)
          File.read(path)
        rescue StandardError => e
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{e.class}: #{e.message}"
          options[:verbose] ? warn("ERR #{display_path}: #{state[:error_messages][path]}") : print('E')
          nil
        end

        # Method documentation.
        #
        # @private
        # @param [Object] path Param documentation.
        # @param [Object] src Param documentation.
        # @param [Object] conf Param documentation.
        # @param [Object] display_path Param documentation.
        # @param [Hash] options Param documentation.
        # @param [Object] state Param documentation.
        # @raise [StandardError]
        # @return [Object]
        # @return [nil] if StandardError
        def rewrite_result_for_path(path, src:, conf:, display_path:, options:, state:)
          Docscribe::InlineRewriter.rewrite_with_report(
            src,
            strategy: options[:strategy],
            config: conf,
            file: path
          )
        rescue StandardError => e
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{e.class}: #{e.message}"
          options[:verbose] ? warn("ERR #{display_path}: #{state[:error_messages][path]}") : print('E')
          nil
        end

        # Method documentation.
        #
        # @private
        # @param [Object] path Param documentation.
        # @param [Object] src Param documentation.
        # @param [Object] out Param documentation.
        # @param [Object] file_changes Param documentation.
        # @param [Object] display_path Param documentation.
        # @param [Hash] options Param documentation.
        # @param [Object] state Param documentation.
        # @return [Object]
        def handle_check_result(path, src:, out:, file_changes:, display_path:, options:, state:)
          if out == src
            options[:verbose] ? puts("OK #{display_path}") : print('.')
            state[:checked_ok] += 1
            return
          end

          if options[:verbose]
            puts("FAIL #{display_path}")
            if options[:explain]
              file_changes.each do |change|
                puts("  - #{format_change_reason(change)}")
              end
            end
          else
            print('F')
          end

          state[:checked_fail] += 1
          state[:changed] = true
          state[:fail_paths] << path
          state[:fail_changes][path] = file_changes
        end

        # Method documentation.
        #
        # @private
        # @param [Object] path Param documentation.
        # @param [Object] src Param documentation.
        # @param [Object] out Param documentation.
        # @param [Object] file_changes Param documentation.
        # @param [Object] display_path Param documentation.
        # @param [Hash] options Param documentation.
        # @param [Object] state Param documentation.
        # @raise [StandardError]
        # @return [Object]
        # @return [Object] if StandardError
        def handle_write_result(path, src:, out:, file_changes:, display_path:, options:, state:)
          if out == src
            options[:verbose] ? puts("OK #{display_path}") : print('.')
            return
          end

          File.write(path, out)

          if options[:verbose]
            puts("CHANGED #{display_path}")
            if options[:explain]
              file_changes.each do |change|
                puts("  - #{format_change_reason(change)}")
              end
            end
          else
            print('C')
          end

          state[:corrected] += 1
        rescue StandardError => e
          state[:had_errors] = true
          state[:error_paths] << path
          state[:error_messages][path] = "#{e.class}: #{e.message}"
          options[:verbose] ? warn("ERR #{display_path}: #{state[:error_messages][path]}") : print('E')
        end

        # Method documentation.
        #
        # @private
        # @param [Object] state Param documentation.
        # @param [Hash] options Param documentation.
        # @return [Object]
        def print_check_summary(state:, options:)
          puts

          checked_error = state[:error_paths].size

          if state[:checked_fail].zero? && checked_error.zero?
            puts "Docscribe: OK (#{state[:checked_ok]} files checked)"
            return
          end

          puts "Docscribe: FAILED (#{state[:checked_fail]} files need updates, #{checked_error} errors, #{state[:checked_ok]} ok)"

          state[:fail_paths].each do |p|
            warn "Would update docs: #{p}"
            next unless options[:explain] && !options[:verbose]

            Array(state[:fail_changes][p]).each do |change|
              warn "  - #{format_change_reason(change)}"
            end
          end

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

        # Method documentation.
        #
        # @private
        # @param [Object] state Param documentation.
        # @return [Object]
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
