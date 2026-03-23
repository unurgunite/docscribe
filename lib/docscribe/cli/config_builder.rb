# frozen_string_literal: true

require 'docscribe/config'

module Docscribe
  module CLI
    module ConfigBuilder
      module_function

      # Build an effective config by applying CLI overrides on top of a base config.
      #
      # CLI overrides currently affect:
      # - method/file include and exclude filters
      # - RBS enablement and additional signature directories
      #
      # If no relevant CLI override is present, the original config is returned unchanged.
      #
      # @note module_function: when included, also defines #build (instance visibility: private)
      # @param [Docscribe::Config] base base config loaded from YAML/defaults
      # @param [Hash] options parsed CLI options
      # @return [Docscribe::Config] merged effective config
      def build(base, options)
        needs_override =
          options[:include].any? || options[:exclude].any? ||
          options[:include_file].any? || options[:exclude_file].any? ||
          options[:rbs]

        return base unless needs_override

        raw = Marshal.load(Marshal.dump(base.raw))
        raw['filter'] ||= {}

        raw['filter']['include'] = Array(raw['filter']['include']) + options[:include]
        raw['filter']['exclude'] = Array(raw['filter']['exclude']) + options[:exclude]

        raw['filter']['files'] ||= {}
        raw['filter']['files']['include'] = Array(raw['filter']['files']['include']) + options[:include_file]
        raw['filter']['files']['exclude'] = Array(raw['filter']['files']['exclude']) + options[:exclude_file]

        if options[:rbs]
          raw['rbs'] ||= {}
          raw['rbs']['enabled'] = true
          raw['rbs']['sig_dirs'] = Array(raw['rbs']['sig_dirs']) + options[:sig_dirs] if options[:sig_dirs].any?
        end

        Docscribe::Config.new(raw)
      end
    end
  end
end
