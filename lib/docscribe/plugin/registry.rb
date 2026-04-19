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
      @tag_plugins = []
      @collector_plugins = []

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
      # @raise [ArgumentError] if plugin type cannot be determined
      # @return [void]
      def register(plugin)
        if plugin.is_a?(Base::CollectorPlugin) || plugin.respond_to?(:collect)
          @collector_plugins << plugin
        elsif plugin.is_a?(Base::TagPlugin) || plugin.respond_to?(:call)
          @tag_plugins << plugin
        else
          raise ArgumentError, 'Plugin must respond to #call (TagPlugin) or #collect (CollectorPlugin)'
        end
      end

      # All registered tag plugins in registration order.
      #
      # @note module_function: when included, also defines #tag_plugins (instance visibility: private)
      # @return [Array<#call>]
      def tag_plugins
        @tag_plugins.dup
      end

      # All registered collector plugins in registration order.
      #
      # @note module_function: when included, also defines #collector_plugins (instance visibility: private)
      # @return [Array<#collect>]
      def collector_plugins
        @collector_plugins.dup
      end

      # Remove all registered plugins.
      #
      # Primarily used in tests to reset state between examples.
      #
      # @note module_function: when included, also defines #clear! (instance visibility: private)
      # @return [void]
      def clear!
        @tag_plugins.clear
        @collector_plugins.clear
      end
    end
  end
end
