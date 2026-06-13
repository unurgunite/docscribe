# frozen_string_literal: true

require 'docscribe/cli/init'
require 'docscribe/cli/generate'
require 'docscribe/cli/options'
require 'docscribe/cli/run'

module Docscribe
  # CLI entry point and command dispatch.
  module CLI
    class << self
      # Main CLI entry point.
      #
      # Dispatches:
      # - `docscribe init ...`     to the config-template generator
      # - `docscribe generate ...` to the plugin skeleton generator
      # - all other commands to the main option parser and runner
      #
      # @param [Array<String>] argv raw command-line arguments
      # @return [Integer] process exit code
      def run(argv)
        argv = argv.dup
        return dispatch_subcommand(argv) if subcommand?(argv.first)

        options = Docscribe::CLI::Options.parse!(argv)
        Docscribe::CLI::Run.run(options: options, argv: argv)
      end

      private

      # Method documentation.
      #
      # @private
      # @param [String?] cmd Param documentation.
      # @return [Boolean]
      def subcommand?(cmd)
        %w[init generate].include?(cmd)
      end

      # Method documentation.
      #
      # @private
      # @param [Array<String>] argv Param documentation.
      # @return [Integer]
      def dispatch_subcommand(argv)
        case argv.first
        when 'init'
          argv.shift
          Docscribe::CLI::Init.run(argv)
        when 'generate'
          argv.shift
          Docscribe::CLI::Generate.run(argv)
        else
          0
        end
      end
    end
  end
end
