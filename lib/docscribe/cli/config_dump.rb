# frozen_string_literal: true

require 'json'
require 'optparse'
require 'yaml'
require 'docscribe/config'
require 'docscribe/cli/config_builder'
require 'docscribe/cli/options'

module Docscribe
  module CLI
    # Print the fully resolved configuration as YAML, JSON or text,
    # optionally limited to the keys that differ from the built-in defaults.
    module ConfigDump
      BANNER = <<~TEXT
        Usage: docscribe config [options]

        Print the fully resolved configuration.

        Options:
      TEXT

      class << self
        # @param [Array<String>] argv
        # @return [Integer]
        def run(argv)
          opts = parse_options(argv)
          return 0 if opts[:help]

          conf = build_config(argv, opts)
          data = opts[:only_changed] ? changed_from_defaults(conf.raw) : conf.raw
          puts render(data, conf, opts)
          0
        end

        private

        # @private
        # @param [Array<String>] argv
        # @return [Hash<Symbol, Object>]
        def parse_options(argv)
          opts = { config: nil, only_changed: false, format: 'yaml' }
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
            o.on('--only-changed', 'Show only keys that differ from defaults') { opts[:only_changed] = true }
            o.on('--format FORMAT', %w[yaml json text], 'Output format: yaml, json, text') { |v| opts[:format] = v }
            o.on('-h', '--help', 'Show help') do
              opts[:help] = true
              puts o
            end
          end
        end

        # @private
        # @param [Array<String>] argv
        # @param [Hash<Symbol, Object>] opts
        # @return [Docscribe::Config]
        def build_config(argv, opts)
          conf = Docscribe::Config.load(opts[:config])
          Docscribe::CLI::ConfigBuilder.build(conf, parse_cli_overrides(argv))
        end

        # @private
        # @param [Array<String>] argv
        # @return [Hash<Symbol, Object>]
        def parse_cli_overrides(argv)
          opts = Docscribe::CLI::Options.parse!(argv)
          opts.slice(:rbs, :rbs_collection, :sorbet, :sig_dirs, :rbi_dirs, :include, :exclude, :include_file,
                     :exclude_file)
        end

        # Keep only the nested keys whose effective value differs from the
        # built-in default.
        #
        # @private
        # @param [Hash<String, Object>] effective merged config
        # @return [Hash<String, Object>]
        def changed_from_defaults(effective)
          diff_against(Docscribe::Config::DEFAULT, effective)
        end

        # Recursive comparison; a single overridden leaf keeps its parent
        # sections while untouched siblings are dropped.
        #
        # @private
        # @param [Hash<String, Object>] defaults
        # @param [Hash<String, Object>] effective
        # @return [Hash<String, Object>]
        def diff_against(defaults, effective)
          effective.each_with_object({}) do |(key, value), acc|
            default = defaults[key]
            if value.is_a?(Hash) && default.is_a?(Hash)
              nested = diff_against(default, value)
              acc[key] = nested unless nested.empty?
            elsif value != default
              acc[key] = value
            end
          end
        end

        # @private
        # @param [Hash<String, Object>] data
        # @param [Docscribe::Config] conf
        # @param [Hash<Symbol, Object>] opts
        # @return [String]
        def render(data, conf, opts)
          case opts[:format]
          when 'json' then JSON.pretty_generate(data)
          when 'text' then render_text(data, conf)
          else data.to_yaml
          end
        end

        # @private
        # @param [Hash<String, Object>] data
        # @param [Docscribe::Config] _conf unused, kept for format symmetry
        # @return [String]
        def render_text(data, _conf)
          flat = flatten(data, '')
          return "(no changes from defaults)\n" if flat.empty?

          flat.map { |key, value| "#{key}=#{value}" }.join("\n")
        end

        # @private
        # @param [Hash<String, Object>] data
        # @param [String] prefix dotted path of the current level
        # @return [Hash<String, Object>]
        def flatten(data, prefix)
          data.each_with_object({}) do |(key, value), acc|
            path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
            if value.is_a?(Hash)
              acc.merge!(flatten(value, path))
            else
              acc[path] = value
            end
          end
        end
      end
    end
  end
end
