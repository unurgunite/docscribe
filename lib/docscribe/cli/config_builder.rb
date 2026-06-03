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
      # - Sorbet enablement and RBI directories
      #
      # If no relevant CLI override is present, the original config is returned unchanged.
      #
      # @note module_function: when included, also defines #build (instance visibility: private)
      # @param [Docscribe::Config] base base config loaded from YAML/defaults
      # @param [Hash] options parsed CLI options
      # @return [Docscribe::Config] merged effective config
      def build(base, options)
        return base unless needs_override?(options)

        raw = Marshal.load(Marshal.dump(base.raw))
        apply_filter_overrides(raw, options)
        apply_rbs_overrides(raw, options) if options[:rbs] || options[:rbs_collection] || options[:sig_dirs].any?
        apply_sorbet_overrides(raw, options) if options[:sorbet] || options[:rbi_dirs].any?
        Docscribe::Config.new(raw)
      end

      # Whether any CLI override is present.
      #
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Hash] options parsed CLI options
      # @return [Boolean]
      def needs_override?(options)
        options[:include].any? ||
          options[:exclude].any?      ||
          options[:include_file].any? ||
          options[:exclude_file].any? ||
          options[:rbs]               ||
          options[:rbs_collection]    ||
          options[:sig_dirs].any?     ||
          options[:sorbet]            ||
          options[:rbi_dirs].any?
      end

      # Apply method and file filter overrides to the raw config.
      #
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Hash] raw raw config hash
      # @param [Hash] options parsed CLI options
      # @return [void]
      def apply_filter_overrides(raw, options)
        raw['filter'] ||= {}
        raw['filter']['include'] = Array(raw['filter']['include']) + options[:include]
        raw['filter']['exclude'] = Array(raw['filter']['exclude']) + options[:exclude]

        raw['filter']['files'] ||= {}
        raw['filter']['files']['include'] = Array(raw['filter']['files']['include']) + options[:include_file]
        raw['filter']['files']['exclude'] = Array(raw['filter']['files']['exclude']) + options[:exclude_file]
      end

      # Apply RBS-related CLI overrides to the raw config.
      #
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Hash] raw raw config hash
      # @param [Hash] options parsed CLI options
      # @return [void]
      def apply_rbs_overrides(raw, options)
        raw['rbs'] ||= {}
        raw['rbs']['enabled'] = true
        raw['rbs']['sig_dirs'] = Array(raw['rbs']['sig_dirs']) + options[:sig_dirs] if options[:sig_dirs].any?

        return unless options[:rbs_collection]

        require 'docscribe/types/rbs/collection_loader'
        collection_path = Docscribe::Types::RBS::CollectionLoader.resolve
        if collection_path
          raw['rbs']['collection_dirs'] = Array(raw['rbs']['collection_dirs']) + [collection_path]
        else
          warn 'Docscribe: rbs_collection.lock.yaml not found or collection not installed. ' \
               'Run `bundle exec rbs collection install` first.'
        end
      end

      # Apply Sorbet-related CLI overrides to the raw config.
      #
      # @note module_function: when included, also defines # (instance visibility: private)
      # @private
      # @param [Hash] raw raw config hash
      # @param [Hash] options parsed CLI options
      # @return [void]
      def apply_sorbet_overrides(raw, options)
        raw['sorbet'] ||= {}
        raw['sorbet']['enabled'] = true
        return unless options[:rbi_dirs].any?

        raw['sorbet']['rbi_dirs'] = Array(raw['sorbet']['rbi_dirs']) + options[:rbi_dirs]
      end
    end
  end
end
