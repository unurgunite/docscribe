# frozen_string_literal: true

module Docscribe
  module Plugin
    # @!attribute [rw] node
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] container
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] scope
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] visibility
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] method_name
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] inferred_params
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] inferred_return
    #   @return [Object]
    #   @param [Object] value
    #
    # @!attribute [rw] source
    #   @return [Object]
    #   @param [Object] value
    Context = Struct.new(
      :node,
      :container,
      :scope,
      :visibility,
      :method_name,
      :inferred_params,
      :inferred_return,
      :source,
      keyword_init: true
    )
  end
end
