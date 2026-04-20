# frozen_string_literal: true

module Docscribe
  class Config
    # Load and register plugins declared under `plugins.require` in config.
    #
    # Each entry is expanded relative to the current working directory and
    # passed to `require`. Registration is expected to happen inside the
    # required file via {Docscribe::Plugin::Registry.register}.
    #
    # Loading failures are non-fatal: a warning is printed and the run
    # continues without the plugin.
    #
    # @raise [LoadError]
    # @return [void]
    def load_plugins!
      paths = Array(raw.dig('plugins', 'require')).compact
      return if paths.empty?

      require 'docscribe/plugin'

      paths.each do |path|
        require File.expand_path(path)
      rescue LoadError => e
        warn "Docscribe: could not load plugin #{path.inspect}: #{e.message}"
      end
    end
  end
end
