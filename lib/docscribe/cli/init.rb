# frozen_string_literal: true

require 'optparse'
require 'docscribe/config'

module Docscribe
  module CLI
    # Generate starter Docscribe configuration.
    module Init
      class << self
        # Create or print a starter Docscribe configuration file.
        #
        # Supported behaviors:
        # - write `docscribe.yml` (default)
        # - write to a custom path via `--config`
        # - overwrite an existing file via `--force`
        # - print the template to STDOUT via `--stdout`
        #
        # @param [Array<String>] argv command-line arguments for `docscribe init`
        # @return [Integer] process exit code
        def run(argv)
          opts = parse_init_options(argv)
          return 0 if opts[:help]

          yaml = Docscribe::Config.default_yaml

          if opts[:stdout]
            puts yaml
            return 0
          end

          write_init_config(opts, yaml)
        end

        private

        # Parse CLI options for `docscribe init`.
        #
        # @private
        # @param [Array<String>] argv Param documentation.
        # @return [Hash<Symbol, Object>] parsed options
        def parse_init_options(argv)
          opts = default_init_options
          build_init_parser(opts).parse!(argv)
          opts
        end

        # Return the default options hash for the init command.
        #
        # @private
        # @return [{ config: "docscribe.yml", force: false, stdout: false, help: false }]
        def default_init_options
          { config: 'docscribe.yml', force: false, stdout: false, help: false }
        end

        # Build and return an OptionParser for the init command.
        #
        # @private
        # @param [Hash<Symbol, Object>] opts options hash that the parser populates
        # @return [OptionParser]
        def build_init_parser(opts)
          OptionParser.new do |o|
            o.banner = 'Usage: docscribe init [options]'
            o.on('--config PATH', 'Where to write the config (default: docscribe.yml)') { |v| opts[:config] = v }
            o.on('-f', '--force', 'Overwrite if the file already exists') { opts[:force] = true }
            o.on('--stdout', 'Print config template to STDOUT instead of writing a file') { opts[:stdout] = true }
            o.on('-h', '--help', 'Show this help') do
              opts[:help] = true
              puts o
            end
          end
        end

        # Write the config template to a file.
        #
        # @private
        # @param [Hash<Symbol, Object>] opts parsed options
        # @param [String] yaml config template content
        # @return [Integer] exit code
        def write_init_config(opts, yaml)
          path = opts[:config]
          if File.exist?(path) && !opts[:force]
            warn "Config already exists: #{path} (use --force to overwrite)"
            return 1
          end

          File.write(path, yaml)
          puts "Created: #{path}"
          0
        end
      end
    end
  end
end
