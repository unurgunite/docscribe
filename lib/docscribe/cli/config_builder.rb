# frozen_string_literal: true

require 'docscribe/config'

module Docscribe
  module CLI
    # Build and override effective config from CLI flags.
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
        filter_overrides?(options) ||
          rbs_overrides?(options) ||
          sorbet_overrides?(options)
      end

      # Whether any method or file filter CLI options were provided.
      #
      # @note module_function: when included, also defines #filter_overrides? (instance visibility: private)
      # @param [Hash] options parsed CLI options
      # @return [Boolean]
      def filter_overrides?(options)
        options[:include].any? ||
          options[:exclude].any?      ||
          options[:include_file].any? ||
          options[:exclude_file].any?
      end

      # Whether any RBS-related CLI options were provided.
      #
      # @note module_function: when included, also defines #rbs_overrides? (instance visibility: private)
      # @param [Hash] options parsed CLI options
      # @return [Boolean]
      def rbs_overrides?(options)
        options[:rbs] ||
          options[:rbs_collection] ||
          options[:sig_dirs].any?
      end

      # Whether any Sorbet-related CLI options were provided.
      #
      # @note module_function: when included, also defines #sorbet_overrides? (instance visibility: private)
      # @param [Hash] options parsed CLI options
      # @return [Boolean]
      def sorbet_overrides?(options)
        options[:sorbet] ||
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
        apply_method_filters(raw, options)
        apply_file_filters(raw, options)
      end

      # Merge CLI method include/exclude patterns into the raw config hash.
      #
      # @note module_function: when included, also defines #apply_method_filters (instance visibility: private)
      # @param [Hash] raw raw config hash
      # @param [Hash] options parsed CLI options
      # @return [void]
      def apply_method_filters(raw, options)
        raw['filter'] ||= {}
        raw['filter']['include'] = Array(raw['filter']['include']) + options[:include]
        raw['filter']['exclude'] = Array(raw['filter']['exclude']) + options[:exclude]
      end

      # Merge CLI file include/exclude patterns into the raw config hash.
      #
      # @note module_function: when included, also defines #apply_file_filters (instance visibility: private)
      # @param [Hash] raw raw config hash
      # @param [Hash] options parsed CLI options
      # @return [void]
      def apply_file_filters(raw, options)
        files = raw['filter']['files'] ||= {} #: Hash[String, untyped]
        files['include'] = Array(files['include']) + options[:include_file]
        files['exclude'] = Array(files['exclude']) + options[:exclude_file]
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

        apply_rbs_collection(raw)
      end

      # Resolve and apply the RBS collection path into the raw config hash.
      #
      # @note module_function: when included, also defines #apply_rbs_collection (instance visibility: private)
      # @param [Hash] raw raw config hash
      # @return [void]
      def apply_rbs_collection(raw)
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
