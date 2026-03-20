# frozen_string_literal: true

module Docscribe
  module Infer
    # Default fallback type used when inference cannot be certain.
    FALLBACK_TYPE = 'Object'

    # Ruby's implicit rescue target for bare `rescue`.
    DEFAULT_ERROR = 'StandardError'
  end
end
