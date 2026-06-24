# frozen_string_literal: true

require 'docscribe/cli/options'
require 'docscribe/cli/run'

module Docscribe
  # CLI entry point and command dispatch.
  module CLI
    class << self
      # @param [Array<String>] argv
      # @return [Integer]
      def run(argv)
        argv = argv.dup
        return dispatch_subcommand(argv) if subcommand?(argv.first)

        options = Docscribe::CLI::Options.parse!(argv)
        Docscribe::CLI::Run.run(options: options, argv: argv)
      end

      COMMANDS = {
        'init' => :Init,
        'generate' => :Generate,
        'sigs' => :Sigs,
        'rbs' => :RbsGen,
        'update_types' => :UpdateTypes,
        'check_for_comments' => :CheckForComments,
        'server' => :ServerCmd
      }.freeze

      private

      # @private
      # @param [String?] cmd
      # @return [Boolean]
      def subcommand?(cmd)
        COMMANDS.key?(cmd)
      end

      # @private
      # @param [Array<String>] argv
      # @return [Integer]
      def dispatch_subcommand(argv)
        cmd = argv.shift
        const_name = COMMANDS[cmd]
        return 0 unless const_name

        require "docscribe/cli/#{cmd == 'rbs' ? 'rbs_gen' : cmd}"
        Docscribe::CLI.const_get(const_name).run(argv)
      end
    end
  end
end
