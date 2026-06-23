# frozen_string_literal: true

module SuppressErrorHelper
  def suppress_error
    yield
  rescue StandardError
    nil
  end
end
