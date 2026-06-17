# frozen_string_literal: true

require 'optparse'

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
      BANNER = <<~TEXT
        Usage: docscribe update_types [directory]

        Two-pass type-aware documentation update.

        Pass 1 (aggressive):  docscribe -AkB --rbs-collection <dir>
          rebuild doc blocks, keep descriptions, no boilerplate

        Pass 2 (safe):        docscribe -aB --rbs-collection <dir>
          safe merge cleanup, no boilerplate

      TEXT

      class << self
        # @param [Array<String>] argv
        # @return [Integer]
        def run(argv)
          options = parse_options(argv)
          dir = options[:dir]

          announce_start

          exit1 = run_first_pass(dir)
          return exit1 unless exit1.zero?

          exit2 = run_second_pass(dir)
          return exit2 unless exit2.zero?

          announce_complete
          0
        end

        private

        # @private
        # @param [Array<String>] argv
        # @return [Hash{Symbol => Object}]
        def parse_options(argv)
          options = { dir: '.' }
          OptionParser.new(BANNER) do |opts|
            opts.on('-h', '--help', 'Show this help') { puts opts or exit 0 }
            opts.parse!(argv)
          end
          options[:dir] = argv.first if argv.any?
          options
        end

        # @private
        # @return [void]
        def announce_start
          puts 'Docscribe: Running type-aware documentation update...'
          puts
        end

        # @private
        # @param [String] dir
        # @return [Integer]
        def run_first_pass(dir)
          puts 'Pass 1: Aggressive rebuild with RBS collection...'
          argv1 = ['-AkB', '--rbs-collection', dir]
          options1 = Docscribe::CLI::Options.parse!(argv1)
          Docscribe::CLI::Run.run(options: options1, argv: [dir])
        end

        # @private
        # @param [String] dir
        # @return [Integer]
        def run_second_pass(dir)
          puts 'Pass 2: Safe merge with RBS collection...'
          argv2 = ['-aB', '--rbs-collection', dir]
          options2 = Docscribe::CLI::Options.parse!(argv2)
          Docscribe::CLI::Run.run(options: options2, argv: [dir])
        end

        # @private
        # @return [void]
        def announce_complete
          puts
          puts 'Docscribe: Type-aware documentation update complete.'
        end
      end
    end
  end
end
