# frozen_string_literal: true

require 'optparse'

module Docscribe
  module CLI
    module Options
      DEFAULT = {
        stdin: false,
        mode: :check,       # :check, :write, :stdin
        strategy: :safe,    # :safe, :aggressive
        verbose: false,
        explain: false,
        config: nil,
        include: [],
        exclude: [],
        include_file: [],
        exclude_file: [],
        rbs: false,
        sig_dirs: []
      }.freeze

      module_function

      # Parse CLI options.
      #
      # Modes:
      # - default => inspect/check safe changes
      # - -a      => write safe changes
      # - -A      => write aggressive changes
      # - --stdin => read from stdin and print rewritten output
      #
      # @param argv [Array<String>]
      # @return [Hash]
      def parse!(argv)
        options = Marshal.load(Marshal.dump(DEFAULT))

        autocorrect_mode = nil

        parser = OptionParser.new do |opts|
          opts.banner = <<~TEXT
            Usage: docscribe [options] [files...]

            Default behavior:
                Inspect files and report what safe doc updates would be applied.

            Autocorrect:
                -a, --autocorrect              Apply safe doc updates in place
                                               (insert missing docs, merge existing doc-like blocks,
                                               normalize tag order)
                -A, --autocorrect-all          Apply aggressive doc updates in place
                                               (rebuild existing doc blocks)

            Input / config:
                    --stdin                    Read code from STDIN and print rewritten output
                -C, --config PATH              Path to config YAML (default: docscribe.yml)

            Type information:
                    --rbs                      Use RBS signatures for @param/@return when available
                    --sig-dir DIR              Add an RBS signature directory (repeatable)

            Filtering:
                    --include PATTERN          Include PATTERN (method id or file path; glob or /regex/)
                    --exclude PATTERN          Exclude PATTERN (method id or file path; glob or /regex/)
                    --include-file PATTERN     Only process files matching PATTERN (glob or /regex/)
                    --exclude-file PATTERN     Skip files matching PATTERN (glob or /regex/)

            Output:
                    --verbose                  Print per-file actions
                    --explain                  Show detailed reasons for changes

            Other:
                -v, --version                  Print version and exit
                -h, --help                     Show this help
          TEXT

          opts.on('-a', '--autocorrect',
                  'Apply safe doc updates in place') do
            autocorrect_mode = :safe
          end

          opts.on('-A', '--autocorrect-all',
                  'Apply aggressive doc updates in place') do
            autocorrect_mode = :aggressive
          end

          opts.on('--stdin', 'Read code from STDIN and print rewritten output') do
            options[:stdin] = true
          end

          opts.on('-C', '--config PATH', 'Path to config YAML (default: docscribe.yml)') do |v|
            options[:config] = v
          end

          opts.on('--rbs', 'Use RBS signatures for @param/@return when available (falls back to inference)') do
            options[:rbs] = true
          end

          opts.on('--sig-dir DIR', 'Add an RBS signature directory (repeatable). Implies --rbs.') do |v|
            options[:rbs] = true
            options[:sig_dirs] << v
          end

          opts.on('--include PATTERN', 'Include PATTERN (method id or file path; glob or /regex/)') do |v|
            route_include_exclude(options, :include, v)
          end

          opts.on('--exclude PATTERN',
                  'Exclude PATTERN (method id or file path; glob or /regex/). Exclude wins.') do |v|
            route_include_exclude(options, :exclude, v)
          end

          opts.on('--include-file PATTERN', 'Only process files matching PATTERN (glob or /regex/)') do |v|
            options[:include_file] << v
          end

          opts.on('--exclude-file PATTERN', 'Skip files matching PATTERN (glob or /regex/). Exclude wins.') do |v|
            options[:exclude_file] << v
          end

          opts.on('--verbose', 'Print per-file actions') do
            options[:verbose] = true
          end

          opts.on('--explain', 'Show detailed reasons for changes') do
            options[:explain] = true
          end

          opts.on('-v', '--version', 'Print version and exit') do
            require 'docscribe/version'
            puts Docscribe::VERSION
            exit 0
          end

          opts.on('-h', '--help', 'Show this help') do
            puts opts
            exit 0
          end
        end

        parser.parse!(argv)

        if options[:stdin]
          options[:mode] = :stdin
          options[:strategy] = autocorrect_mode || :safe
        elsif autocorrect_mode
          options[:mode] = :write
          options[:strategy] = autocorrect_mode
        else
          options[:mode] = :check
          options[:strategy] = :safe
        end

        options
      end

      # Route include/exclude patterns into file filters or method filters.
      #
      # @param options [Hash]
      # @param kind [Symbol]
      # @param value [String]
      # @return [void]
      def route_include_exclude(options, kind, value)
        if looks_like_file_pattern?(value)
          options[:"#{kind}_file"] << value
        else
          options[kind] << value
        end
      end

      # @param pat [String]
      # @return [Boolean]
      def looks_like_file_pattern?(pat)
        return false if pat.start_with?('/') && pat.end_with?('/') && pat.length >= 2

        pat.include?('/') || pat.include?('**') || pat.end_with?('.rb')
      end
    end
  end
end
