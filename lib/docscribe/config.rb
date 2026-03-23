# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'psych'

module Docscribe
  class Config
    # Raw config hash after deep-merging user config with defaults.
    #
    # @return [Hash]
    #
    # @!attribute [r] raw
    #   @return [Object]
    attr_reader :raw

    # Create a configuration object from a raw config hash.
    #
    # Missing keys are filled from {DEFAULT} via deep merge.
    #
    # @param [Hash, nil] raw user-provided config hash
    # @return [void]
    def initialize(raw = {})
      @raw = deep_merge(DEFAULT, raw || {})
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
