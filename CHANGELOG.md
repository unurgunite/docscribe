## 1.4.2

### Added

- Architecture module-flow and data-flow diagrams to README.md
- RBS signatures are now split per-file alongside their `lib/` sources (was monolithic `sig/lib/docscribe.rbs`)
- `Steepfile` for `steep check` with `#:` type annotations on safe trailing-comment positions
- `SECURITY.md`, `CONTRIBUTING.md`, issue templates, and PR template for GitHub community standards

### Fixed

- Nilable type warnings in steep (89→57):
  - `source_helpers.rb`: guard `src[...]`, `lines[...]` with `|| ""` / `|| []`
  - `inline_rewriter.rb`: guard `src`/`lines`, `anchor_node`, `param_types`, `visibility`
  - `doc_builder.rb`: guard `type_match[1]`, `m[1]`, `treat_options_keyword_as_hash`, `setup`
  - `collector.rb`: `!!(node && .type)` for `self_node?`, guard `args`
  - `returns.rb`: guard `node.children[]`, `recv`, default kwargs to `unify_types`
  - `provider.rb`: guard `@builder`, fallback `name || :Object`
  - `generate.rb`: guard `output_dir`/`class_name` with `|| '.'` / `|| ''`
- RBS signature fixes: `?collapse_generics` as optional keyword arg, `apply_attr_aggressive!` 2-arg signature
- CLI `dispatch_subcommand` now guarantees `Integer` return (`else 0`)
- CI compatibility for Ruby 3.0/3.1: rbs 4.x requires Ruby ≥ 3.2, excluded via `BUNDLE_WITHOUT`

### Changed

- Major RuboCop compliance sweep across `lib/`, `spec/`, `examples/`
- CLI layer refactored (`options.rb`, `run.rb`, `generate.rb`, `init.rb`, `config_builder.rb`)
- Core rewriter engine refactored (`inline_rewriter.rb`, `collector.rb`, `doc_builder.rb`, `doc_block.rb`, `tag_sorter.rb`)
- Type system helpers refactored (`rbs/provider.rb`, `rbs/type_formatter.rb`, `sorbet/base_provider.rb`, `infer/returns.rb`)
- Plugin system dispatch simplified (`plugin.rb`, `registry.rb`, `base/collector_plugin.rb`)
- `.rubocop.yml` / `.rubocop_todo.yml` updated with tighter thresholds

## 1.4.1

### Added

- `method_override` key for CollectorPlugins — structured patches (`return_type`, `param_types`, `tags`) that merge
  into the standard DocBuilder pipeline instead of replacing it entirely
- `param_types` override for `@param` tags (merges on top of inference, external sig still wins)
- `tags` override appends arbitrary YARD tags (supports `Docscribe::Plugin::Tag` and plain Hash, incl. string keys)
- Plugin doc normalization: tag-only CollectorPlugin output gets default method message prepended for `def/defs` anchors
- Unit tests for `method_override`: `param_types`, `tags`, priority, string-keyed Hash tags

### Fixed

- `build_override_plugin` test helper not forwarding `tags` to constructor
- `rewrite_with_report` default `config:` (`nil` instead of `Docscribe::Config.new({})`)
- `--include '*/get'` glob pattern now correctly routes as method filter instead of file filter
- `match_pattern?` translates `/` to `#` in glob patterns so `*/get` matches `ApiClient#get`
- ModelAttributes `build_method_docs` processes each class with its own table columns instead of using the first model's columns for the entire AST

### Changed

- ModelAttributes plugin converted from `doc:` to `method_override:` (dead code removed)
- ModelAttributes plugin now supports `defs` (class methods) and works with aggressive mode
- ModelAttributes `string_method?` / `infer_string_method_type` now includes `truncate`

## 1.4.0 (2026-05-30)

### Added

- `Registry.register(plugin, priority: N)` for deterministic plugin priority (default `0`)
- CollectorPlugin deduplication — highest-priority plugin wins at each source position
- New example plugins: `RailsAssociations`, `SchemaAttributes`, `ModelAttributes`

### Changed

- Plugin registration now requires explicit `register` call (breaking change for pre-1.4.0)

## 1.3.3 (2026-05-23)

### Fixed

- `--rbs-collection` not reporting type mismatches due to `RBS::DuplicatedDeclarationError` being silently caught
- Collection signatures stored separately from user sig_dirs to prevent poisoning the RBS environment

## 1.3.2 (2026-05-23)

### Added

- `--rbs` and `--rbs-collection` dry-run mode reports type mismatches (shown as `M` in output)

### Fixed

- `RBS::TypeName.parse` compatibility with RBS < 3.9 (Ruby 3.0)
- Safe strategy no longer overwrites manually set `@param` / `@return` types
- `--rbs-collection` flag correctly enables RBS provider

## 1.3.1 (2026-05-09)

### Fixed

- Return type inference for methods with keyword arguments
- Safe mode now updates existing `@return` and `@param` tags when types change
- Consistent `Boolean` inference between `--rbs` and `--rbs-collection`
- Config `DEFAULT` hash now matches template YAML from `docscribe init`

### Added

- Warning when `--rbs*` flags are used on Ruby < 3.0 (falls back to inference)

### Changed

- CI no longer deploys documentation/gem (done locally)

## 1.3.0 (2026-04-27)

### Added

- Plugin system: `TagPlugin` and `CollectorPlugin` base classes
- Enhanced custom RBS parser

## 1.2.1 (2026-03-28)

### Added

- Config options to disable default method descriptions and param placeholder text

## 1.2.0 (2026-03-28)

### Added

- RBS type signature support (`--rbs`, `--rbs-collection`)
- `docscribe init` command
- `attr_*` method documentation generator
- Sorbet signature support via external type providers (`--sorbet`)
- Configurable `@param` / `@return` tag sorting
- `@!attribute` docs for `Struct.new` declarations
- Merge rewrite strategy
- Improved visibility handling (`module_function`, private/public)

### Changed

- Major codebase refactoring
- CLI update strategies simplified

## 1.1.0 (2026-01-16)

### Added

- Support for Ruby 2.7 and Ruby 4.0

## 1.0.0 (2025-11-12)

### Added

- Initial release — inline documentation rewriting for `def` / `def self.` methods
- Safe and aggressive rewrite strategies
- YARD-compatible doc generation with `@param`, `@return`
- RBS inference for parameter and return types
- CLI interface
