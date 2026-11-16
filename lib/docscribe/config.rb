# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'psych'

module Docscribe
  # Application configuration with deep-merge defaults and overrides.
  class Config
    # @!attribute [r] raw
    #   @return [Hash<String, Object>]
    attr_reader :raw

    # @!attribute [r] config_path
    #   @return [String?]
    attr_reader :config_path

    # Create a configuration object from a raw config hash.
    #
    # Missing keys are filled from {DEFAULT} via deep merge.
    #
    # @param [String?] config_path optional path to the config file
    # @param [Hash<String, Object>] raw user-provided config hash
    # @return [void]
    def initialize(config_path: nil, **raw)
      @raw = deep_merge(DEFAULT, stringify_keys(raw))
      @config_path = config_path
    end

    # Resolve a config-relative path against the config root.
    #
    # Absolute paths are returned unchanged without touching the filesystem;
    # relative paths are expanded from the config root rather than the process
    # working directory.
    #
    # @param [String] path path as written in the config file or CLI
    # @return [String] absolute path
    def resolve_path(path)
      absolute = Pathname.new(path.to_s).absolute?
      return path.to_s if absolute

      File.expand_path(path.to_s, config_root)
    end

    # Directory that relative paths in the config file resolve against.
    #
    # This is the directory containing `docscribe.yml`, so `sig_dirs`,
    # `rbi_dirs`, `plugins.require` and the RBS collection lock file resolve the
    # same whether Docscribe runs from the project root or from a subdirectory.
    # Without a config file it falls back to the current working directory.
    #
    # @raise [Docscribe::Error] when the config directory no longer exists
    # @return [String] absolute path to the config root
    def config_root
      return File.expand_path(Dir.pwd) unless config_path

      root = File.expand_path(File.dirname(config_path))
      return root if File.directory?(root)

      raise Docscribe::Error, "Docscribe: config directory not found for #{config_path.inspect} (resolved #{root})"
    end

    # @return [Object]
    def to_h
      hash = {} #: Hash[String, Object]
      instance_variables.each do |var|
        key = var.to_s.sub('@', '')
        hash[key] = instance_variable_get(var)
      end
      hash
    end
  end
end

require_relative 'config/defaults'
require_relative 'config/utils'
require_relative 'config/loader'
require_relative 'config/template'
require_relative 'config/emit'
require_relative 'config/filtering'
require_relative 'config/rbs'
require_relative 'config/sorting'
require_relative 'config/sorbet'
require_relative 'config/plugin'
require_relative 'config/validation'
