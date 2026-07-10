# frozen_string_literal: true

require 'optparse'
require 'docscribe/config'

module Docscribe
  module CLI
    # Generate starter Docscribe configuration.
    module Init
      BANNER = <<~TEXT
        Usage: docscribe init [options]

        Generate a starter docscribe.yml configuration file.

        Options:
      TEXT

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
        # @param [Array<String>] argv command-line arguments for `docscribe init`
        # @return [Hash<Symbol, Object>] parsed options
        def parse_init_options(argv)
          opts = default_init_options
          build_init_parser(opts).parse!(argv)
          opts
        end

        # Return the default options hash for the init command.
        #
        # @private
        # @return [Hash<Symbol, String, Boolean>]
        def default_init_options
          { config: 'docscribe.yml', force: false, stdout: false, help: false, pre_commit: false }
        end

        # Build and return an OptionParser for the init command.
        #
        # @private
        # @param [Hash<Symbol, Object>] opts options hash that the parser populates
        # @return [OptionParser]
        def build_init_parser(opts)
          OptionParser.new do |o|
            o.banner = BANNER
            o.on('--config PATH', 'Where to write the config (default: docscribe.yml)') { |v| opts[:config] = v }
            o.on('-f', '--force', 'Overwrite if the file already exists') { opts[:force] = true }
            o.on('--stdout', 'Print config template to STDOUT instead of writing a file') { opts[:stdout] = true }
            o.on('--pre-commit', 'Install pre-commit hook for docscribe check') { opts[:pre_commit] = true }
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
          return install_pre_commit_hook(opts) if opts[:pre_commit]

          path = opts[:config]
          if File.exist?(path) && !opts[:force]
            warn "Config already exists: #{path} (use --force to overwrite)"
            return 1
          end

          File.write(path, yaml)
          puts "Created: #{path}"
          0
        end

        # @private
        # @param [Object] opts
        # @return [Integer]
        def install_pre_commit_hook(opts)
          hook_dir = File.join('.git', 'hooks')
          hook_path = File.join(hook_dir, 'pre-commit')

          unless Dir.exist?(hook_dir)
            warn 'No .git/hooks directory found. Are you in a git repository?'
            return 1
          end

          if File.exist?(hook_path) && !opts[:force]
            warn "Pre-commit hook already exists: #{hook_path} (use --force to overwrite)"
            return 1
          end

          hook_content = <<~HOOK
            #!/bin/sh
            # Docscribe pre-commit hook
            # Runs docscribe check on staged Ruby files

            STAGED_RUBY_FILES=$(git diff --cached --name-only --diff-filter=ACM -- '*.rb')
            if [ -z "$STAGED_RUBY_FILES" ]; then
              exit 0
            fi

            echo "Checking documentation with docscribe..."
            bundle exec docscribe check $STAGED_RUBY_FILES
            RESULT=$?

            if [ $RESULT -ne 0 ]; then
              echo "Documentation check failed. Please add documentation before committing."
              exit 1
            fi

            exit 0
          HOOK

          File.write(hook_path, hook_content)
          File.chmod(0o755, hook_path)
          puts "Installed pre-commit hook: #{hook_path}"
          0
        end
      end
    end
  end
end
