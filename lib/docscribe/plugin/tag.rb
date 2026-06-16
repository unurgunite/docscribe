# frozen_string_literal: true

module Docscribe
  module Plugin
    # @!attribute [rw] name
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] text
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] types
    #   @return [Object]
    #   @param [Object] value
    Tag = Struct.new(:name, :text, :types, keyword_init: true)
  end
end
