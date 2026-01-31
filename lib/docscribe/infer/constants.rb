# frozen_string_literal: true

module Docscribe
  module Infer
    # Default fallback type when inference cannot be certain.
    FALLBACK_TYPE = 'Object'

    # Ruby's implicit rescue target.
    DEFAULT_ERROR = 'StandardError'
  end
end
