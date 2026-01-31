# frozen_string_literal: true

require 'optparse'
require 'docscribe/config'

module Docscribe
  module CLI
    module Init
      class << self
        # @param argv [Array<String>]
        # @return [Integer]
        def run(argv)
          opts = {
            config: 'docscribe.yml',
            force: false,
            stdout: false
          }

          OptionParser.new do |o|
            o.banner = 'Usage: docscribe init [options]'
            o.on('--config PATH', 'Where to write the config (default: docscribe.yml)') { |v| opts[:config] = v }
            o.on('-f', '--force', 'Overwrite if the file already exists') { opts[:force] = true }
            o.on('--stdout', 'Print config template to STDOUT instead of writing a file') { opts[:stdout] = true }
            o.on('-h', '--help', 'Show this help') do
              puts o
              return 0
            end
          end.parse!(argv)

          yaml = Docscribe::Config.default_yaml

          if opts[:stdout]
            puts yaml
            return 0
          end

          path = opts[:config]
          if File.exist?(path) && !opts[:force]
            warn "Config already exists: #{path} (use --force to overwrite)"
            return 1
          end

          File.write(path, yaml)
          puts "Created: #{path}"
          0
        end
      end
    end
  end
end
