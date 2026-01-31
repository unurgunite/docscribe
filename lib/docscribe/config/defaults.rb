# frozen_string_literal: true

module Docscribe
  class Config
    # Default configuration values used when no docscribe.yml is present or keys are missing.
    DEFAULT = {
      'emit' => {
        'header' => true,
        'param_tags' => true,
        'return_tag' => true,
        'visibility_tags' => true,
        'raise_tags' => true,
        'rescue_conditional_returns' => true
      },
      'doc' => {
        'default_message' => 'Method documentation.'
      },
      'methods' => {
        'instance' => {
          'public' => {},
          'protected' => {},
          'private' => {}
        },
        'class' => {
          'public' => {},
          'protected' => {},
          'private' => {}
        }
      },
      'inference' => {
        'fallback_type' => 'Object',
        'nil_as_optional' => true,
        'treat_options_keyword_as_hash' => true
      },
      'filter' => {
        'visibilities' => %w[public protected private],
        'scopes' => %w[instance class],
        'include' => [],
        'exclude' => [],
        'files' => {
          'include' => [],
          'exclude' => []
        }
      },
      'rbs' => {
        'enabled' => false,
        'sig_dirs' => ['sig'],
        'collapse_generics' => false
      }
    }.freeze
  end
end
