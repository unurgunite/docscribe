# frozen_string_literal: true

module Docscribe
  class Config
    # Whether sortable tag normalization is enabled for doc-like blocks.
    #
    # @return [Boolean]
    def sort_tags?
      raw.dig('doc', 'sort_tags') != false
    end

    # Configured sortable tag order.
    #
    # Tags are normalized without a leading `@`.
    #
    # @return [Array<String>]
    def tag_order
      Array(raw.dig('doc', 'tag_order') || DEFAULT.dig('doc', 'tag_order')).map do |t|
        t.to_s.sub(/\A@/, '')
      end
    end
  end
end
