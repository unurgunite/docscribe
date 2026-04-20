# frozen_string_literal: true

require 'docscribe/plugin'

module DocscribePlugins
  # Appends an +@api+ visibility tag to every documented method.
  #
  # Public methods receive +@api public+; protected and private methods
  # receive +@api private+. This mirrors the convention used by many
  # YARD-documented gems and is a minimal but realistic TagPlugin example.
  #
  # @example Registration
  #   require 'examples/plugins/tag_plugin/plugin'
  #   Docscribe::Plugin::Registry.register(DocscribePlugins::ApiTagPlugin.new)
  #
  # @example Public method output
  #   # @api public
  #   # @return [Integer]
  #   def count
  #     @items.size
  #   end
  #
  # @example Private method output
  #   # @api private
  #   # @private
  #   # @return [String]
  #   def format_name(name)
  #     name.strip
  #   end
  class ApiTagPlugin < Docscribe::Plugin::Base::TagPlugin
    # Generate an +@api+ tag for the given method context.
    #
    # @param [Docscribe::Plugin::Context] context method context snapshot
    # @return [Array<Docscribe::Plugin::Tag>]
    def call(context)
      label = public_visibility?(context) ? 'public' : 'private'
      [Docscribe::Plugin::Tag.new(name: 'api', text: label)]
    end

    private

    # Whether the method is considered part of the public API.
    #
    # @private
    # @param [Docscribe::Plugin::Context] context
    # @return [Boolean]
    def public_visibility?(context)
      context.visibility == :public
    end
  end
end
