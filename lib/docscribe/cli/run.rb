# frozen_string_literal: true

require 'pathname'

require 'docscribe/cli/config_builder'
require 'docscribe/inline_rewriter'

module Docscribe
  module CLI
    module Run
      module_function

      # @param options [Hash]
      # @return [Integer]
      # @param argv [Array<String>]
      def run(options:, argv:)
        conf = Docscribe::Config.load(options[:config])
        conf = Docscribe::CLI::ConfigBuilder.build(conf, options)

        if options[:rewrite] && options[:merge]
          warn 'Docscribe: cannot combine --refresh and --merge. Choose one.'
          return 1
        end

        return run_stdin(options: options, conf: conf) if options[:stdin]

        unless options[:write]
          options[:check] = true
          options[:merge] = true
        end

        paths = expand_paths(argv)
        paths = paths.select { |p| conf.process_file?(p) }

        if paths.empty?
          warn 'No files found. Pass files or directories (e.g. `docscribe --dry lib`).'
          return 1
        end

        if !options[:check] && !options[:write]
          warn 'No mode selected. Use --dry, --write, or --stdin. See --help.'
          return 1
        end

        if options[:check] && options[:write]
          warn 'Docscribe: both --dry/--check and --write were provided; running in --dry mode (no files will be modified).'
        end

        run_files(options: options, conf: conf, paths: paths)
      end

      # @param options [Hash]
      # @param conf [Docscribe::Config]
      # @return [Integer]
      # @return [Integer] if StandardError
      def run_stdin(options:, conf:)
        code = $stdin.read
        result = Docscribe::InlineRewriter.rewrite_with_report(
          code,
          rewrite: options[:rewrite],
          merge: options[:merge],
          config: conf,
          file: '(stdin)'
        )
        puts result[:output]
        0
      rescue StandardError => e
        warn "Docscribe: Error processing stdin: #{e.class}: #{e.message}"
        1
      end

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

      # @param options [Hash]
      # @param conf [Docscribe::Config]
      # @param paths [Array<String>]
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
                rewrite: options[:rewrite],
                merge: options[:merge],
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

          if options[:check]
            if out == src
              options[:verbose] ? puts("OK #{display_path}") : print('.')
              checked_ok += 1
            else
              if options[:verbose]
                puts("FAIL #{display_path}")
                file_changes.each do |change|
                  puts("  - #{format_change_reason(change)}")
                end
              else
                print('F')
              end

              checked_fail += 1
              changed = true
              fail_paths << path
            end

          elsif options[:write]
            if out == src
              options[:verbose] ? puts("OK #{display_path}") : print('.')
            else
              begin
                File.write(path, out)
                if options[:verbose]
                  puts("CHANGED #{display_path}")
                  file_changes.each do |change|
                    puts("  - #{format_change_reason(change)}")
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

        if options[:check]
          puts

          # If we had any errors, count them separately in the summary.
          checked_error = error_paths.size

          if checked_fail.zero? && checked_error.zero?
            puts "Docscribe: OK (#{checked_ok} files checked)"
          else
            out = "Docscribe: FAILED (#{checked_fail} files need updates, #{checked_error} errors, #{checked_ok} ok)."
            out += " Use `--verbose' for details." unless options[:verbose]
            puts out
            fail_paths.each { |p| warn "Would update docs: #{p}" }
            error_paths.each do |p|
              warn "Error processing: #{p}"
              warn "  #{error_messages[p]}" if error_messages[p]
            end
          end

        elsif options[:write]
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

        # Exit status:
        # - check mode: fail if any file would change OR any errors happened
        # - write mode: fail if any errors happened
        return 1 if had_errors

        options[:check] && changed ? 1 : 0
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

        # If abs is under pwd, show clean relative path.
        pwd_str = pwd.to_s
        abs_str = abs.to_s
        return abs.relative_path_from(pwd).to_s if abs_str.start_with?(pwd_str + File::SEPARATOR)

        # Otherwise avoid ugly ../../../../ paths in output.
        File.basename(abs_str)
      rescue StandardError
        File.basename(path.to_s)
      end

      private_class_method :format_change_reason, :display_path_for
    end
  end
end
