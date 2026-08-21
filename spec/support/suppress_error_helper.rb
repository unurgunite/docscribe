# frozen_string_literal: true

module SuppressErrorHelper
  # Method documentation.
  #
  # @raise [StandardError]
  # @return [Object]
  # @return [nil] if StandardError
  def suppress_error
    yield
  rescue StandardError
    nil
  end
end
