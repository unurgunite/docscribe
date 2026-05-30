# frozen_string_literal: true

module Docscribe
  module Plugin
    # Global plugin registry.
    #
    # Plugins are registered once at boot time (e.g. in a file loaded via
    # `plugins.require:` in docscribe.yml) and called for every file Docscribe
    # processes.
    #
    # Thread safety: registration is expected to happen before any parallel
    # rewriting begins.
    module Registry
      # @!attribute [rw] plugin
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] priority
      #   @return [Object]
      #   @param [Object] value
      #
      # @!attribute [rw] order
      #   @return [Object]
      #   @param [Object] value
      Entry = Struct.new(:plugin, :priority, :order, keyword_init: true)

      @tag_entries = []
      @collector_entries = []
      @order_seq = 0

      module_function

      # Register a plugin.
      #
      # Routes to the appropriate list based on plugin type:
      # - subclass of Base::TagPlugin       => tag plugin
      # - subclass of Base::CollectorPlugin => collector plugin
      # - responds to #call                 => tag plugin (duck typing)
      # - responds to #collect              => collector plugin (duck typing)
      #
      # @note module_function: when included, also defines #register (instance visibility: private)
      # @param [Object] plugin plugin instance
      # @param [Integer] priority plugin priority (higher wins for conflicts)
      # @raise [ArgumentError] if plugin type cannot be determined
      # @raise [StandardError]
      # @return [void]
      def register(plugin, priority: 0)
        prio =
          begin
            Integer(priority)
          rescue StandardError
            raise ArgumentError, "priority must be an Integer-like value, got: #{priority.inspect}"
          end

        @order_seq += 1
        entry = Entry.new(plugin: plugin, priority: prio, order: @order_seq)

        if plugin.is_a?(Base::CollectorPlugin) || plugin.respond_to?(:collect)
          @collector_entries << entry
        elsif plugin.is_a?(Base::TagPlugin) || plugin.respond_to?(:call)
          @tag_entries << entry
        else
          raise ArgumentError, 'Plugin must respond to #call (TagPlugin) or #collect (CollectorPlugin)'
        end
      end

      # All registered tag plugins in registration order.
      #
      # @note module_function: when included, also defines #tag_plugins (instance visibility: private)
      # @return [Array<#call>]
      def tag_plugins
        @tag_entries.map(&:plugin)
      end

      # All registered collector plugins in registration order.
      #
      # @note module_function: when included, also defines #collector_plugins (instance visibility: private)
      # @return [Array<#collect>]
      def collector_plugins
        @collector_entries.map(&:plugin)
      end

      # All registered tag plugin entries (plugin + priority metadata).
      #
      # @note module_function: when included, also defines #tag_entries (instance visibility: private)
      # @return [Array<Entry>]
      def tag_entries
        @tag_entries.dup
      end

      # All registered collector plugin entries (plugin + priority metadata).
      #
      # @note module_function: when included, also defines #collector_entries (instance visibility: private)
      # @return [Array<Entry>]
      def collector_entries
        @collector_entries.dup
      end

      # Remove all registered plugins.
      #
      # Primarily used in tests to reset state between examples.
      #
      # @note module_function: when included, also defines #clear! (instance visibility: private)
      # @return [void]
      def clear!
        @tag_entries.clear
        @collector_entries.clear
        @order_seq = 0
      end
    end
  end
end
