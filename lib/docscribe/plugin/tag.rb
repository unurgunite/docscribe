# frozen_string_literal: true

module Docscribe
  module Plugin
    # @!attribute [rw] name
    #   @return [String]
    #   @param [String] value
    #
    # @!attribute [rw] text
    #   @return [String, nil]
    #   @param [String, nil] value
    #
    # @!attribute [rw] types
    #   @return [Array<String>, nil]
    #   @param [Array<String>, nil] value
    Tag = Struct.new(:name, :text, :types, keyword_init: true)
  end
end
