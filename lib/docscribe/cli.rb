# frozen_string_literal: true

require 'docscribe/cli/init'
require 'docscribe/cli/options'
require 'docscribe/cli/run'

module Docscribe
  module CLI
    class << self
      # Main CLI entry point.
      #
      # Dispatches:
      # - `docscribe init ...` to the config-template generator
      # - all other commands to the main option parser and runner
      #
      # @param [Array<String>] argv raw command-line arguments
      # @return [Integer] process exit code
      def run(argv)
        argv = argv.dup

        if argv.first == 'init'
          argv.shift
          return Docscribe::CLI::Init.run(argv)
        end

        options = Docscribe::CLI::Options.parse!(argv)
        Docscribe::CLI::Run.run(options: options, argv: argv)
      end
    end
  end
end
