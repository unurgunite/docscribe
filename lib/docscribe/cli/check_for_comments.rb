# frozen_string_literal: true

require 'optparse'

require 'docscribe/config/defaults'
require 'docscribe/config/loader'
require 'docscribe/config/emit'

module Docscribe
  module CLI
    # Check for default placeholder text in generated documentation.
    #
    # Usage:
    #   docscribe check_for_comments [paths...]
    #
    # Reads the configured placeholder messages from docscribe.yml (or defaults)
    # and scans Ruby source files for YARD comments containing those placeholders.
    # Exits non-zero if any are found.
    module CheckForComments
      BANNER = <<~TEXT
        Usage: docscribe check_for_comments [paths...]

        Check for default placeholder documentation text in Ruby source files.

        Reads placeholder messages from docscribe.yml config (or built-in defaults)
        and scans .rb files for YARD comments still containing that text.

        Useful in CI to catch auto-generated text that should have been replaced.
      TEXT

      class << self
        # @param [Array<String>] argv
        # @return [Integer]
        def run(argv)
          config = Docscribe::Config.load
          placeholders = resolve_placeholders(config)
          return no_placeholders_configured if placeholders.empty?

          parse_options(argv)
          paths = expand_paths(argv)
          return no_paths if paths.empty?

          results = scan_paths(paths, placeholders)
          process_results(results)
        end

        private

        # @private
        # @param [Docscribe::Config] config
        # @return [Array<String>]
        def resolve_placeholders(config)
          default_msg = raw_or_default(config, %w[doc default_message])
          param_doc = config.param_documentation
          [default_msg, param_doc].compact.uniq
        end

        # @private
        # @param [Docscribe::Config] config
        # @param [Array<String>] keys nested keys
        # @return [String, nil]
        def raw_or_default(config, keys)
          raw = config.raw.dig(*keys)
          return raw if raw

          Docscribe::Config::DEFAULT.dig(*keys)
        end

        # @private
        # @return [Integer]
        def no_placeholders_configured
          warn 'Docscribe: No placeholder messages configured. Nothing to check.'
          0
        end

        # @private
        # @param [Array<String>] argv
        # @return [void]
        def parse_options(argv)
          OptionParser.new(BANNER) do |opts|
            opts.on('-h', '--help', 'Show this help') { puts opts or exit 0 }
          end.parse!(argv)
        end

        # @private
        # @param [Array<String>] args
        # @return [Array<String>]
        def expand_paths(args)
          files = [] #: Array[String]
          args = ['.'] if args.empty?
          args.each { |path| expand_single_path(files, path) }
          files.uniq.sort
        end

        # @private
        # @param [Array<String>] files
        # @param [String] path
        # @return [void]
        def expand_single_path(files, path)
          if File.directory?(path)
            files.concat(Dir.glob(File.join(path, '**', '*.rb')))
          elsif File.file?(path) && path.end_with?('.rb')
            files << path
          elsif File.file?(path)
            warn "Skipping non-Ruby file: #{path}"
          else
            warn "Skipping missing path: #{path}"
          end
        end

        # @private
        # @return [Integer]
        def no_paths
          warn 'No files found. Pass files or directories (e.g. `docscribe check_for_comments lib`).'
          1
        end

        # @private
        # @param [Array<String>] paths
        # @param [Array<String>] placeholders
        # @return [Array<[String, Array<[Integer, String]>]>]
        def scan_paths(paths, placeholders)
          paths.filter_map { |path| scan_file(path, placeholders) }
        end

        # @private
        # @param [Array<[String, Array<[Integer, String]>]>] results
        # @return [Integer]
        def process_results(results)
          if results.empty?
            puts 'Docscribe: No placeholder documentation found.'
            0
          else
            report(results)
            1
          end
        end

        # @private
        # @param [String] path
        # @param [Array<String>] placeholders
        # @return [(String, Array<[Integer, String]>)?]
        def scan_file(path, placeholders)
          lines = File.readlines(path)
          matches = [] #: Array[[Integer, String]]

          lines.each_with_index do |line, idx|
            next unless comment_line?(line)

            placeholders.each do |placeholder|
              matches << [idx + 1, line.strip] if line.include?(placeholder)
            end
          end

          [path, matches] if matches.any?
        end

        # @private
        # @param [String] line
        # @return [Boolean]
        def comment_line?(line)
          line.strip.start_with?('#')
        end

        # @private
        # @param [Array<[String, Array<[Integer, String]>]>] results
        # @return [void]
        def report(results)
          total = results.sum { |_path, matches| matches.size }
          puts "Docscribe: Found #{total} placeholder(s) in #{results.size} file(s):"
          puts

          results.each do |path, matches|
            matches.each do |line_num, text|
              puts "  #{path}:#{line_num}  #{text}"
            end
          end
        end
      end
    end
  end
end
