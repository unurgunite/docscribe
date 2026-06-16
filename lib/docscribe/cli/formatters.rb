# frozen_string_literal: true

module Docscribe
  module CLI
    # Factory for output formatters.
    module Formatters
      # Method documentation.
      #
      # @raise [ArgumentError]
      # @param [Object] format Param documentation.
      # @return [Text, Json, Object]
      def self.for(format)
        case format
        when :text then Text.new
        when :json then Json.new
        else raise ArgumentError, "Unknown format: #{format}"
        end
      end
    end
  end
end

require_relative 'formatters/text'
require_relative 'formatters/json'
