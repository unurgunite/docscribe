# frozen_string_literal: true

require 'docscribe/cli/init'
require 'docscribe/cli/generate'
require 'docscribe/cli/options'
require 'docscribe/cli/run'

module Docscribe
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

        case argv.first
        when 'init'
          argv.shift
          return Docscribe::CLI::Init.run(argv)
        when 'generate'
          argv.shift
          return Docscribe::CLI::Generate.run(argv)
        end

        options = Docscribe::CLI::Options.parse!(argv)
        Docscribe::CLI::Run.run(options: options, argv: argv)
      end
    end
  end
end
