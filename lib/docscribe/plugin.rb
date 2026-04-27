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
    # @param [Docscribe::Plugin::Context] context
    # @raise [StandardError]
    # @return [Array<Docscribe::Plugin::Tag>]
    def self.run_tag_plugins(context)
      Registry.tag_plugins.flat_map do |plugin|
        plugin.call(context)
      rescue StandardError => e
        warn "Docscribe: TagPlugin #{plugin.class} raised #{e.class}: #{e.message}" if debug?
        []
      end
    end

    # Run all registered CollectorPlugins for one file's AST.
    #
    # @param [Parser::AST::Node] ast
    # @param [Parser::Source::Buffer] buffer
    # @raise [StandardError]
    # @return [Array<Hash>]
    def self.run_collector_plugins(ast, buffer)
      Registry.collector_plugins.flat_map do |plugin|
        plugin.collect(ast, buffer)
      rescue StandardError => e
        warn "Docscribe: CollectorPlugin #{plugin.class} raised #{e.class}: #{e.message}" if debug?
        []
      end
    end

    # @return [Boolean]
    def self.debug?
      ENV['DOCSCRIBE_DEBUG'] == '1'
    end
  end
end
