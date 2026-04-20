# frozen_string_literal: true

module Docscribe
  module Plugin
    # A single YARD-style tag returned by a TagPlugin.
    #
    # @example Simple tag
    #   Tag.new(name: 'since', text: '1.3.0')
    #   # => # @since 1.3.0
    #
    # @example Tag with types
    #   Tag.new(name: 'raise', types: ['ArgumentError'], text: 'if name is nil')
    #   # => # @raise [ArgumentError] if name is nil
    #
    # @!attribute name
    #   @return [String] tag name without leading @
    # @!attribute text
    #   @return [String, nil] text after the type bracket
    # @!attribute types
    #   @return [Array<String>, nil] optional type list rendered as [Foo, Bar]
    Tag = Struct.new(:name, :text, :types, keyword_init: true)
  end
end
