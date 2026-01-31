# frozen_string_literal: true

require 'docscribe/cli/init'
require 'docscribe/cli/options'
require 'docscribe/cli/run'

module Docscribe
  module CLI
    class << self
      # Main CLI entry point.
      #
      # @param argv [Array<String>]
      # @return [Integer] exit code
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
