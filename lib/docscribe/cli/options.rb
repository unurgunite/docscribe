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
        sig_dirs: [],
        sorbet: false,
        rbi_dirs: [],
        rbs_collection: false
      }.freeze

      module_function

      # Parse CLI arguments into normalized Docscribe runtime options.
      #
      # CLI behavior model:
      # - default: inspect mode using the safe strategy
      # - `-a` / `--autocorrect`: write mode using the safe strategy
      # - `-A` / `--autocorrect-all`: write mode using the aggressive strategy
      # - `--stdin`: stdin mode using the selected strategy (safe by default)
      #
      # Filtering, config, verbosity, and external type options are applied
      # orthogonally.
      #
      # @note module_function: when included, also defines #parse! (instance visibility: private)
      # @param [Array<String>] argv raw CLI arguments
      # @return [Hash] normalized runtime options
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
                    --sig-dir DIR              Add an RBS signature directory (repeatable). Implies `--rbs`.
                    --sorbet                   Use Sorbet signatures from inline sigs / RBI files when available
                    --rbi-dir DIR              Add a Sorbet RBI directory (repeatable). Implies --sorbet.
                    --rbs-collection           Auto-discover RBS collection from rbs_collection.lock.yaml. Implies --rbs.

            Filtering:
                    --include PATTERN          Include PATTERN (method id or file path; glob or /regex/)
                    --exclude PATTERN          Exclude PATTERN (method id or file path; glob or /regex/)
                    --include-file PATTERN     Only process files matching PATTERN (glob or /regex/)
                    --exclude-file PATTERN     Skip files matching PATTERN (glob or /regex/)

            Output:
                    --verbose                  Print per-file actions
                -e, --explain                  Show detailed reasons for changes

            Other:
                -v, --version                  Print version and exit
                -h, --help                     Show this help
          TEXT

          opts.on('-a', '--autocorrect', 'Apply safe doc updates in place') do
            autocorrect_mode = :safe
          end

          opts.on('-A', '--autocorrect-all', 'Apply aggressive doc updates in place') do
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

          opts.on('--sorbet', 'Use Sorbet signatures from inline sigs / RBI files when available') do
            options[:sorbet] = true
          end

          opts.on('--rbi-dir DIR', 'Add a Sorbet RBI directory (repeatable). Implies --sorbet.') do |v|
            options[:sorbet] = true
            options[:rbi_dirs] << v
          end

          opts.on('--rbs-collection', 'Auto-discover RBS collection from rbs_collection.lock.yaml. Implies --rbs.') do
            options[:rbs] = true
            options[:rbs_collection] = true
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

          opts.on('-e', '--explain', 'Show detailed reasons for changes') do
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

      # Route an include/exclude pattern into method filters or file filters.
      #
      # Regex-looking patterns (`/…/`) are treated as method-id filters.
      # File-like patterns are routed into `*_file`.
      #
      # @note module_function: when included, also defines #route_include_exclude (instance visibility: private)
      # @param [Hash] options mutable parsed options hash
      # @param [Symbol] kind either :include or :exclude
      # @param [String] value raw pattern from the CLI
      # @return [void]
      def route_include_exclude(options, kind, value)
        if looks_like_file_pattern?(value)
          options[:"#{kind}_file"] << value
        else
          options[kind] << value
        end
      end

      # Heuristically decide whether a pattern looks like a file path or file glob.
      #
      # Regex syntax (`/.../`) is intentionally treated as a method-id pattern,
      # not a file pattern.
      #
      # @note module_function: when included, also defines #looks_like_file_pattern? (instance visibility: private)
      # @param [String] pat pattern passed via CLI
      # @return [Boolean]
      def looks_like_file_pattern?(pat)
        return false if pat.start_with?('/') && pat.end_with?('/') && pat.length >= 2

        pat.include?('/') || pat.include?('**') || pat.end_with?('.rb')
      end
    end
  end
end
