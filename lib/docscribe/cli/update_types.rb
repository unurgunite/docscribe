# frozen_string_literal: true

require 'docscribe/cli/options'
require 'docscribe/cli/run'

module Docscribe
  module CLI
    # Two-pass update: rebuild docs then re-merge with RBS types.
    #
    # Usage:
    #   docscribe update_types [directory]
    #
    # Pass 1: `-AkB --rbs-collection <dir>` — aggressive rebuild, keep descriptions,
    #   no boilerplate, using RBS collection signatures.
    # Pass 2: `-aB --rbs-collection <dir>` — safe merge cleanup, no boilerplate,
    #   using RBS collection signatures.
    module UpdateTypes
      class << self
        # @param [Array<String>] argv
        # @return [Integer]
        def run(argv)
          dir = argv.first || '.'

          puts 'Docscribe: Running type-aware documentation update...'
          puts

          exit1 = run_pass_1(dir)
          return exit1 unless exit1.zero?

          exit2 = run_pass_2(dir)
          return exit2 unless exit2.zero?

          puts
          puts 'Docscribe: Type-aware documentation update complete.'
          0
        end

        private

        # @private
        # @param [String] dir
        # @return [Integer]
        def run_pass_1(dir)
          puts 'Pass 1: Aggressive rebuild with RBS collection...'
          argv1 = ['-AkB', '--rbs-collection', dir]
          options1 = Docscribe::CLI::Options.parse!(argv1)
          Docscribe::CLI::Run.run(options: options1, argv: [dir])
        end

        # @private
        # @param [String] dir
        # @return [Integer]
        def run_pass_2(dir)
          puts 'Pass 2: Safe merge with RBS collection...'
          argv2 = ['-aB', '--rbs-collection', dir]
          options2 = Docscribe::CLI::Options.parse!(argv2)
          Docscribe::CLI::Run.run(options: options2, argv: [dir])
        end
      end
    end
  end
end
