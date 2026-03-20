# frozen_string_literal: true

require 'pathname'

require 'docscribe/cli/config_builder'
require 'docscribe/inline_rewriter'

module Docscribe
  module CLI
    module Run
      module_function

      # @note module_function: when included, also defines #run (instance visibility: private)
      # @param options [Hash]
      # @param argv [Array<String>]
      # @return [Integer]
      def run(options:, argv:)
        conf = Docscribe::Config.load(options[:config])
        conf = Docscribe::CLI::ConfigBuilder.build(conf, options)

        return run_stdin(options: options, conf: conf) if options[:mode] == :stdin

        paths = expand_paths(argv)
        paths = paths.select { |p| conf.process_file?(p) }

        if paths.empty?
          warn 'No files found. Pass files or directories (e.g. `docscribe lib`).'
          return 1
        end

        run_files(options: options, conf: conf, paths: paths)
      end

      # @note module_function: when included, also defines #run_stdin (instance visibility: private)
      # @param options [Hash]
      # @param conf [Docscribe::Config]
      # @raise [StandardError]
      # @return [Integer]
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

      # @note module_function: when included, also defines #expand_paths (instance visibility: private)
      # @param args [Array<String>]
      # @return [Array<String>]
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

      # @note module_function: when included, also defines #run_files (instance visibility: private)
      # @param options [Hash]
      # @param conf [Docscribe::Config]
      # @param paths [Array<String>]
      # @raise [StandardError]
      # @return [Integer]
      def run_files(options:, conf:, paths:)
        $stdout.sync = true

        changed = false
        had_errors = false

        checked_ok = 0
        checked_fail = 0
        checked_error = 0

        corrected = 0

        fail_paths = []
        fail_changes = {}
        error_paths = []
        error_messages = {}

        pwd = Pathname.pwd

        paths.each do |path|
          display_path = display_path_for(path, pwd: pwd)

          src =
            begin
              File.read(path)
            rescue StandardError => e
              had_errors = true
              error_paths << path
              error_messages[path] = "#{e.class}: #{e.message}"
              options[:verbose] ? warn("ERR #{display_path}: #{error_messages[path]}") : print('E')
              next
            end

          result =
            begin
              Docscribe::InlineRewriter.rewrite_with_report(
                src,
                strategy: options[:strategy],
                config: conf,
                file: path
              )
            rescue StandardError => e
              had_errors = true
              error_paths << path
              error_messages[path] = "#{e.class}: #{e.message}"
              options[:verbose] ? warn("ERR #{display_path}: #{error_messages[path]}") : print('E')
              next
            end

          out = result[:output]
          file_changes = result[:changes] || []

          if options[:mode] == :check
            if out == src
              options[:verbose] ? puts("OK #{display_path}") : print('.')
              checked_ok += 1
            else
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

              checked_fail += 1
              changed = true
              fail_paths << path
              fail_changes[path] = file_changes
            end

          elsif options[:mode] == :write
            if out == src
              options[:verbose] ? puts("OK #{display_path}") : print('.')
            else
              begin
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
                corrected += 1
              rescue StandardError => e
                had_errors = true
                error_paths << path
                error_messages[path] = "#{e.class}: #{e.message}"
                options[:verbose] ? warn("ERR #{display_path}: #{error_messages[path]}") : print('E')
              end
            end
          end
        end

        if options[:mode] == :check
          puts

          checked_error = error_paths.size

          if checked_fail.zero? && checked_error.zero?
            puts "Docscribe: OK (#{checked_ok} files checked)"
          else
            puts "Docscribe: FAILED (#{checked_fail} files need updates, #{checked_error} errors, #{checked_ok} ok)"
            fail_paths.each do |p|
              warn "Would update docs: #{p}"
              if options[:explain] && !options[:verbose]
                Array(fail_changes[p]).each do |change|
                  warn "  - #{format_change_reason(change)}"
                end
              end
            end
            error_paths.each do |p|
              warn "Error processing: #{p}"
              warn "  #{error_messages[p]}" if error_messages[p]
            end
          end

        elsif options[:mode] == :write
          puts
          puts "Docscribe: updated #{corrected} file(s)" if corrected.positive?

          if had_errors
            warn "Docscribe: #{error_paths.size} file(s) had errors"
            error_paths.each do |p|
              warn "Error processing: #{p}"
              warn "  #{error_messages[p]}" if error_messages[p]
            end
          end
        end

        return 1 if had_errors
        return 1 if options[:mode] == :check && changed

        0
      end

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

      def display_path_for(path, pwd:)
        abs = Pathname.new(path).expand_path

        pwd_str = pwd.to_s
        abs_str = abs.to_s
        return abs.relative_path_from(pwd).to_s if abs_str.start_with?(pwd_str + File::SEPARATOR)

        File.basename(abs_str)
      rescue StandardError
        File.basename(path.to_s)
      end

      private_class_method :format_change_reason, :display_path_for
    end
  end
end
