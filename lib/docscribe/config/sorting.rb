# frozen_string_literal: true

module Docscribe
  class Config
    # @return [Boolean]
    def sort_tags?
      raw.dig('doc', 'sort_tags') != false
    end

    # @return [Array<String>]
    def tag_order
      Array(raw.dig('doc', 'tag_order') || DEFAULT.dig('doc', 'tag_order')).map do |t|
        t.to_s.sub(/\A@/, '')
      end
    end
  end
end
