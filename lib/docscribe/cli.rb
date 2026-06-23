# frozen_string_literal: true

require 'docscribe/cli/init'
require 'docscribe/cli/generate'
require 'docscribe/cli/options'
require 'docscribe/cli/run'
require 'docscribe/cli/sigs'
require 'docscribe/cli/rbs_gen'
require 'docscribe/cli/update_types'
require 'docscribe/cli/check_for_comments'
require 'docscribe/cli/server'

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

      COMMANDS = {
        'init' => Docscribe::CLI::Init,
        'generate' => Docscribe::CLI::Generate,
        'sigs' => Docscribe::CLI::Sigs,
        'rbs' => Docscribe::CLI::RbsGen,
        'update_types' => Docscribe::CLI::UpdateTypes,
        'check_for_comments' => Docscribe::CLI::CheckForComments,
        'server' => Docscribe::CLI::ServerCmd
      }.freeze

      private

      # Subcommand
      #
      # @private
      # @param [String?] cmd potential subcommand name
      # @return [Boolean]
      def subcommand?(cmd)
        COMMANDS.key?(cmd)
      end

      # Dispatch subcommand
      #
      # @private
      # @param [Array<String>] argv raw command-line arguments
      # @return [Integer]
      def dispatch_subcommand(argv)
        cmd = argv.shift
        mod = COMMANDS[cmd]
        mod ? mod.run(argv) : 0
      end
    end
  end
end
