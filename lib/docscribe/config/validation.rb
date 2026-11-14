# frozen_string_literal: true

module Docscribe
  # Validation-related configuration.
  class Config
    # Whether to validate YARD types against inferred / external types.
    #
    # When enabled, `docscribe lib --validate-types` (or `validate_types: true`
    # in `docscribe.yml`) compares each `@param`/`@return` type written in YARD
    # against the type inferred from the method body or provided via RBS/Sorbet.
    # Mismatches are reported as `updated_param` / `updated_return` and, in
    # check mode, cause exit 1.
    #
    # @return [Boolean]
    def validate_types?
      fetch_bool(%w[validate_types], false)
    end

    # Whether to report syntactically broken YARD types.
    #
    # Independent of {#validate_types?}: syntax validity is a property of the
    # YARD type string itself, not a comparison against inferred or external
    # types. Enabled by default so a broken `[Sym bol]` is still surfaced (and
    # safely fixed) on plain runs; set `warn_invalid_yard: false` or pass
    # `--no-warn-invalid-yard` to silence it.
    #
    # @return [Boolean]
    def warn_invalid_yard?
      fetch_bool(%w[warn_invalid_yard], true)
    end
  end
end
