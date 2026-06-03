# frozen_string_literal: true

module Docscribe
  module Plugin
    module Base
      # Base class for tag plugins.
      #
      # TagPlugins hook into already-collected method insertions and append
      # additional YARD tags to the generated doc block.
      #
      # @example
      #   class SincePlugin < Docscribe::Plugin::Base::TagPlugin
      #     def initialize(version:)
      #       @version = version
      #     end
      #
      #     def call(context)
      #       [Docscribe::Plugin::Tag.new(name: 'since', text: @version)]
      #     end
      #   end
      #
      #   Docscribe::Plugin::Registry.register(SincePlugin.new(version: '1.3.0'))
      class TagPlugin
        # Generate additional tags for a documented method.
        #
        # Called once per documented method. Return [] if this plugin has
        # nothing to add for this particular method.
        #
        # @param [Docscribe::Plugin::Context] context method context snapshot
        # @param [Object] _context Param documentation.
        # @return [Array<Docscribe::Plugin::Tag>]
        def call(_context)
          []
        end
      end
    end
  end
end
