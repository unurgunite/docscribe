# frozen_string_literal: true

require 'optparse'
require 'yaml'
require 'docscribe/config'
require 'docscribe/cli/config_builder'

module Docscribe
  module CLI
    # Print the fully resolved configuration as YAML.
    module ConfigDump
      BANNER = <<~TEXT
        Usage: docscribe config [options]

        Print the fully resolved configuration as YAML.

        Options:
      TEXT

      class << self
        # @param [Array<String>] argv
        # @return [Integer]
        def run(argv)
          opts = parse_options(argv)
          return 0 if opts[:help]

          conf = Docscribe::Config.load(opts[:config])
          conf = Docscribe::CLI::ConfigBuilder.build(conf, parse_cli_overrides(argv))

          puts conf.to_h.to_yaml
          0
        end

        private

        # @private
        # @param [Array<String>] argv
        # @return [Hash<Symbol, Object>]
        def parse_options(argv)
          opts = { config: nil }
          build_parser(opts).parse!(argv)
          opts
        end

        # @private
        # @param [Hash<Symbol, Object>] opts
        # @return [OptionParser]
        def build_parser(opts)
          OptionParser.new do |o|
            o.banner = BANNER
            o.on('--config PATH', 'Path to config file') { |v| opts[:config] = v }
            o.on('-h', '--help', 'Show help') do
              opts[:help] = true
              puts o
            end
          end
        end

        # @private
        # @param [Array<String>] argv
        # @return [Hash<Symbol, Object>]
        def parse_cli_overrides(argv)
          opts = Docscribe::CLI::Options.parse!(argv)
          opts.slice(:rbs, :rbs_collection, :sorbet, :sig_dirs, :rbi_dirs, :include, :exclude)
        end
      end
    end
  end
end
