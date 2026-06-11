# frozen_string_literal: true

module Docscribe
  module Infer
    # Default fallback type used when inference cannot be certain.
    FALLBACK_TYPE = 'Object'

    # Ruby's implicit rescue target for bare `rescue`.
    DEFAULT_ERROR = 'StandardError'

    # Node type to literal type name mapping.
    LITERAL_TYPE_MAP = {
      int: 'Integer',
      float: 'Float',
      str: 'String',
      dstr: 'String',
      sym: 'Symbol',
      true: 'Boolean',
      false: 'Boolean',
      nil: 'nil',
      array: 'Array',
      hash: 'Hash',
      regexp: 'Regexp'
    }.freeze
  end
end
