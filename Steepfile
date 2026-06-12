# frozen_string_literal: true

target :lib do
  check 'lib'
  signature 'sig'
  collection_config 'rbs_collection.yaml'

  configure_code_diagnostics do |hash|
    # Accept these as non-blocking:
    hash[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = :warning
    hash[Steep::Diagnostic::Ruby::BlockTypeMismatch] = :warning
    hash[Steep::Diagnostic::Ruby::UnknownConstant] = :warning
    hash[Steep::Diagnostic::Ruby::UnresolvedOverloading] = :warning

    # Accept missing methods on `bot` type as warnings
    # (bot arises from prototype sigs with untyped params/hashes)
    hash[Steep::Diagnostic::Ruby::NoMethod] = :warning

    # Accept keyword/hash splat limitations (opts.slice(...)**opts patterns)
    hash[Steep::Diagnostic::Ruby::InsufficientKeywordArguments] = :warning
    hash[Steep::Diagnostic::Ruby::InsufficientPositionalArguments] = :warning

    # Accept proto-sig type mismatches from simplistic rbs prototype rb output
    hash[Steep::Diagnostic::Ruby::ArgumentTypeMismatch] = :warning
    hash[Steep::Diagnostic::Ruby::MethodBodyTypeMismatch] = :warning
    hash[Steep::Diagnostic::Ruby::UnexpectedPositionalArgument] = :warning
    hash[Steep::Diagnostic::Ruby::UnexpectedKeywordArgument] = :warning
  end
end
