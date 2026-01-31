# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'psych'

module Docscribe
  class Config
    attr_reader :raw

    # Create a Docscribe configuration instance.
    #
    # The provided hash is deep-merged into DEFAULT, so any missing keys are filled
    # from defaults.
    #
    # @param raw [Hash, nil]
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
