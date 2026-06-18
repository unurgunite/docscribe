# frozen_string_literal: true

module Docscribe
  module CLI
    # Factory for output formatters.
    module Formatters
      # Select formatter by format type.
      #
      # @param [Docscribe::CLI::Formatters::format] format output format symbol
      # @raise [ArgumentError]
      # @return [Docscribe::CLI::Formatters::Text, Docscribe::CLI::Formatters::Json, Docscribe::CLI::Formatters::Sarif]
      def self.for(format)
        case format
        when :text then Text.new
        when :json then Json.new
        when :sarif then Sarif.new
        else raise ArgumentError, "Unknown format: #{format}"
        end
      end
    end
  end
end

require_relative 'formatters/text'
require_relative 'formatters/json'
require_relative 'formatters/sarif'
