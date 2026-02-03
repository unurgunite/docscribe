# frozen_string_literal: true

require 'docscribe/cli/config_builder'
require 'docscribe/inline_rewriter'

module Docscribe
  module CLI
    module Run
      module_function

      # +Docscribe::CLI::Run#run+ -> Object
      #
      # Method documentation.
      #
      # @param [Hash] options Param documentation.
      # @param [Object] argv Param documentation.
      # @return [Object]
      def run(options:, argv:)
        conf = Docscribe::Config.load(options[:config])
        conf = Docscribe::CLI::ConfigBuilder.build(conf, options)

        if options[:rewrite] && options[:merge]
          warn 'Docscribe: cannot combine --refresh and --merge. Choose one.'
          return 1
        end
        return run_stdin(options: options, conf: conf) if options[:stdin]

        if argv.empty?
          warn 'No input. Use --stdin or pass file paths. See --help.'
          return 1
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

        run_files(options: options, conf: conf, paths: paths)
      end

      # +Docscribe::CLI::Run#run_stdin+ -> Integer
      #
      # Method documentation.
      #
      # @param [Hash] options Param documentation.
      # @param [Object] conf Param documentation.
      # @return [Integer]
      def run_stdin(options:, conf:)
        code = $stdin.read
        out = Docscribe::InlineRewriter.insert_comments(code, rewrite: options[:rewrite], merge: options[:merge],
                                                              config: conf, file: '(stdin)')
        puts out
        0
      rescue StandardError => e
        warn "Docscribe: Error processing stdin: #{e.class}: #{e.message}"
        1
      end

      # +Docscribe::CLI::Run#expand_paths+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] args Param documentation.
      # @return [Object]
      def expand_paths(args)
        files = []
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

      # +Docscribe::CLI::Run#run_files+ -> Integer
      #
      # Method documentation.
      #
      # @param [Hash] options Param documentation.
      # @param [Object] conf Param documentation.
      # @param [Object] paths Param documentation.
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

        paths.each do |path|
          src =
            begin
              File.read(path)
            rescue StandardError => e
              had_errors = true
              error_paths << path
              error_messages[path] = "#{e.class}: #{e.message}"
              print 'E'
              next
            end

          out =
            begin
              Docscribe::InlineRewriter.insert_comments(src, rewrite: options[:rewrite],
                                                             merge: options[:merge], config: conf, file: '(stdin)')
            rescue StandardError => e
              # This is primarily for syntax errors, but we intentionally keep going even on unexpected errors.
              had_errors = true
              error_paths << path
              error_messages[path] = "#{e.class}: #{e.message}"
              print 'E'
              next
            end

          if options[:check]
            if out == src
              print '.'
              checked_ok += 1
            else
              print 'F'
              checked_fail += 1
              changed = true
              fail_paths << path
            end
          elsif options[:write]
            if out == src
              print '.'
            else
              begin
                File.write(path, out)
                print 'C'
                corrected += 1
              rescue StandardError => e
                had_errors = true
                error_paths << path
                error_messages[path] = "#{e.class}: #{e.message}"
                print 'E'
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
            puts "Docscribe: FAILED (#{checked_fail} failing, #{checked_error} errors, #{checked_ok} ok)"
            fail_paths.each { |p| warn "Missing docs: #{p}" }
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
    end
  end
end
