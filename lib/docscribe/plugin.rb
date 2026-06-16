# frozen_string_literal: true

require_relative 'plugin/tag'
require_relative 'plugin/context'
require_relative 'plugin/base/tag_plugin'
require_relative 'plugin/base/collector_plugin'
require_relative 'plugin/registry'

module Docscribe
  # Plugin system entry point.
  #
  # Provides two extension points:
  #
  # 1. TagPlugin — hooks into already-collected method insertions and appends
  #    additional YARD tags. Subclass Base::TagPlugin and override #call.
  #
  # 2. CollectorPlugin — receives the raw AST and walks it independently.
  #    Used for non-standard structures that Docscribe's Collector does not
  #    recognize. Subclass Base::CollectorPlugin and override #collect.
  module Plugin
    # Run all registered TagPlugins for one method context.
    #
    # Errors in individual plugins are caught so one broken plugin does not
    # abort the entire run.
    #
    # @param [Docscribe::Plugin::Context] context Param documentation.
    # @raise [StandardError]
    # @return [Array<Docscribe::Plugin::Tag>]
    def self.run_tag_plugins(context)
      Registry.tag_entries
              # Higher number => higher priority (run earlier).
              # This matters when multiple TagPlugins emit the same tag name
              # and Docscribe deduplicates tags by name.
              .sort_by { |entry| [-entry.priority, entry.order] }
              .flat_map do |entry|
        plugin = entry.plugin
        plugin.call(context)
      rescue StandardError => e
        warn "Docscribe: TagPlugin #{plugin.class} raised #{e.class}: #{e.message}" if debug?
        []
      end
    end

    # Run all registered CollectorPlugins for one file's AST.
    #
    # @param [Parser::AST::Node] ast Param documentation.
    # @param [Parser::Source::Buffer] buffer Param documentation.
    # @return [Array<Hash<Symbol, Object>>]
    def self.run_collector_plugins(ast, buffer)
      Registry.collector_entries.flat_map { |entry| process_single_plugin_result(entry, ast, buffer) }
    end

    # Process a single collector plugin's result.
    #
    # Merges plugin metadata into each hash insertion and handles errors.
    #
    # @param [Docscribe::Plugin::Registry::Entry] entry registry entry with priority and order metadata
    # @param [Parser::AST::Node] ast Param documentation.
    # @param [Parser::Source::Buffer] buffer Param documentation.
    # @raise [StandardError]
    # @return [Array<Hash<Symbol, Object>>] if StandardError
    # @return [Array] if StandardError
    def self.process_single_plugin_result(entry, ast, buffer)
      plugin = entry.plugin
      results = Array(plugin.collect(ast, buffer))
      process_plugin_insertions(results, entry, plugin)
    rescue StandardError => e
      warn "Docscribe: CollectorPlugin #{plugin.class} raised #{e.class}: #{e.message}" if debug?
      []
    end

    # Merge plugin metadata into collector results and filter invalid ones.
    #
    # @param [Array<Object>] results collector plugin results to process
    # @param [Docscribe::Plugin::Registry::Entry] entry registry entry with priority and order metadata
    # @param [Docscribe::Plugin::Base::CollectorPlugin] plugin the collector plugin instance
    # @return [Array<Hash<Symbol, Object>>]
    def self.process_plugin_insertions(results, entry, plugin)
      results.map do |insertion|
        next nil unless valid_plugin_result?(insertion, plugin)

        insertion.merge(
          __docscribe_priority: entry.priority,
          __docscribe_plugin_class: plugin.class.name,
          __docscribe_plugin_order: entry.order
        )
      end.compact
    end

    # Validate a CollectorPlugin result is a Hash.
    #
    # @param [Object] insertion Param documentation.
    # @param [Object] plugin the collector plugin instance
    # @return [Boolean]
    def self.valid_plugin_result?(insertion, plugin)
      return true if insertion.is_a?(Hash)

      warn "Docscribe: CollectorPlugin #{plugin.class} returned #{insertion.class}, expected Hash" if debug?
      false
    end

    # Self
    #
    # @return [Boolean]
    def self.debug?
      ENV['DOCSCRIBE_DEBUG'] == '1'
    end
  end
end
