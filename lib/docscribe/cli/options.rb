# frozen_string_literal: true

require 'optparse'

module Docscribe
  module CLI
    module Options
      DEFAULT = {
        stdin: false,
        write: false,
        check: false,
        rewrite: false, # set by --refresh
        config: nil,

        include: [],
        exclude: [],
        include_file: [],
        exclude_file: [],

        rbs: false,
        sig_dirs: []
      }.freeze

      module_function

      # +Docscribe::CLI::Options#parse!+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] argv Param documentation.
      # @return [Object]
      def parse!(argv)
        options = Marshal.load(Marshal.dump(DEFAULT))

        parser = OptionParser.new do |opts|
          opts.banner = 'Usage: docscribe [options] [files...]'

          opts.on('-d', '-c', '--dry', '--check', 'Dry-run: exit 1 if any file would change') { options[:check] = true }
          opts.on('-w', '--write', 'Rewrite files in place') { options[:write] = true }
          opts.on('-r', '--refresh', 'Regenerate docs: replace existing doc blocks above methods') do
            options[:rewrite] = true
          end

          opts.on('--stdin', 'Read code from STDIN and print with docs inserted') { options[:stdin] = true }
          opts.on('-C', '--config PATH', 'Path to config YAML (default: docscribe.yml)') { |v| options[:config] = v }

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
        options
      end

      # +Docscribe::CLI::Options#route_include_exclude+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] options Param documentation.
      # @param [Object] kind Param documentation.
      # @param [Object] value Param documentation.
      # @return [Object]
      def route_include_exclude(options, kind, value)
        if looks_like_file_pattern?(value)
          options[:"#{kind}_file"] << value
        else
          options[kind] << value
        end
      end

      # +Docscribe::CLI::Options#looks_like_file_pattern?+ -> Object
      #
      # Method documentation.
      #
      # @param [Object] pat Param documentation.
      # @return [Object]
      def looks_like_file_pattern?(pat)
        # Regex patterns are wrapped in slashes (e.g. "/^A#foo$/").
        # Those are commonly used for method-id filtering with --include/--exclude.
        #
        # If you want regex filtering for files, use --include-file/--exclude-file.
        return false if pat.start_with?('/') && pat.end_with?('/') && pat.length >= 2

        pat.include?('/') || pat.include?('**') || pat.end_with?('.rb')
      end
    end
  end
end
