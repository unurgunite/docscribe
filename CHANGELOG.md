## 1.3.1

### Fixed

- Return type inference for methods with keyword arguments (e.g., `def foo(p1: 1, p2: 3); p1 + p2; end` now correctly
  infers `Integer`)
- Safe mode (`-a`) now updates existing `@return` and `@param` tags when types change
- Consistent `Boolean` inference between `--rbs` and `--rbs-collection` flags
- Config consistency: DEFAULT hash now matches template YAML from `docscribe init`

### Added

- Warning when `--rbs*` flags are used on Ruby < 3.0 (falls back to inference)
- Spec for config DEFAULT vs YAML template consistency
- Tests for type updates in safe mode

### Changed

- CI no longer deploys documentation/gem (done locally)
- Refactored RBS core types spec to use modern RSpec style
