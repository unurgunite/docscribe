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
        out = Docscribe::InlineRewriter.insert_comments(code, rewrite: options[:rewrite], config: conf)
        puts out
        0
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
        checked_ok = 0
        checked_fail = 0
        corrected = 0
        fail_paths = []

        paths.each do |path|
          src = File.read(path)
          out = Docscribe::InlineRewriter.insert_comments(src, rewrite: options[:rewrite], config: conf)

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
              File.write(path, out)
              print 'C'
              corrected += 1
            end
          end
        end

        if options[:check]
          puts
          if checked_fail.zero?
            puts "Docscribe: OK (#{checked_ok} files checked)"
          else
            puts "Docscribe: FAILED (#{checked_fail} failing, #{checked_ok} ok)"
            fail_paths.each { |p| warn "Missing docs: #{p}" }
          end
        elsif options[:write]
          puts
          puts "Docscribe: updated #{corrected} file(s)" if corrected.positive?
        end

        options[:check] && changed ? 1 : 0
      end
    end
  end
end
