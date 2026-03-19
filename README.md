# Docscribe

[![Gem Version](https://img.shields.io/gem/v/docscribe.svg)](https://rubygems.org/gems/docscribe)
[![RubyGems Downloads](https://img.shields.io/gem/dt/docscribe.svg)](https://rubygems.org/gems/docscribe)
[![CI](https://github.com/unurgunite/docscribe/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/unurgunite/docscribe/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/unurgunite/docscribe.svg)](https://github.com/unurgunite/docscribe/blob/master/LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.7-blue.svg)](#installation)

Generate inline, YARD-style documentation comments for Ruby methods by analyzing your code's AST.

Docscribe inserts doc headers before method definitions, infers parameter and return types (including rescue-aware
returns),
and respects Ruby visibility semantics — without using YARD to parse.

- No AST reprinting. Your original code, formatting, and constructs (like `class << self`, `heredocs`, `%i[]`) are
  preserved.
- Inline-first. Comments are inserted at the start of each `def`/`defs` line.
- Heuristic type inference for params and return values, including conditional returns in rescue branches.
- Optional refresh mode (`--refresh`) for regenerating existing method docs.
- Ruby 3.4+ syntax supported using Prism translation (see "Parser backend" below).
- Optional RBS integration (`--rbs`, `--sig-dir`) for more accurate `@param`/`@return` types.
- Optional `attr_reader`/`attr_writer`/`attr_accessor` documentation via YARD `@!attribute` (see Configuration).

Common workflows:

- Generate docs (write changes):
  `docscribe --write lib`

- Check in CI (no changes, fails if docs would change):
  `docscribe --dry lib`

- Refresh/rebaseline docs (regenerate existing doc blocks):
  `docscribe --write --refresh lib`

- Use RBS signatures when available:
  `docscribe --rbs --sig-dir sig --write lib`

## Contents

* [Docscribe](#docscribe)
    * [Contents](#contents)
    * [Installation](#installation)
    * [Quick start](#quick-start)
    * [CLI](#cli)
    * [Inline behavior](#inline-behavior)
        * [Refresh mode](#refresh-mode)
        * [Output markers in CI](#output-markers-in-ci)
    * [Parser backend (Parser gem vs Prism)](#parser-backend-parser-gem-vs-prism)
    * [RBS integration (optional)](#rbs-integration-optional)
    * [Type inference](#type-inference)
    * [Rescue-aware returns and @raise](#rescue-aware-returns-and-raise)
    * [Visibility semantics](#visibility-semantics)
    * [API (library) usage](#api-library-usage)
    * [Configuration](#configuration)
        * [Filtering](#filtering)
        * [Create a starter config](#create-a-starter-config)
    * [CI integration](#ci-integration)
    * [Comparison to YARD's parser](#comparison-to-yards-parser)
    * [Limitations](#limitations)
    * [Roadmap](#roadmap)
    * [Contributing](#contributing)
    * [License](#license)

## Installation

Add to your Gemfile:

```ruby
gem "docscribe"
```

Then:

```shell
bundle install
```

Or install globally:

```shell
gem install docscribe
```

Requires Ruby 2.7+.

## Quick start

Given code:

```ruby
class Demo
  def foo(a, options: {})
    42
  end

  def bar(verbose: true)
    123
  end

  private

  def self.bump
    :ok
  end

  class << self
    private

    def internal; end
  end
end
```

Run:

```shell
echo "...code above..." | docscribe --stdin
```

Output:

```ruby
class Demo
  # +Demo#foo+ -> Integer
  #
  # Method documentation.
  #
  # @param [Object] a Param documentation.
  # @param [Hash] options Param documentation.
  # @return [Integer]
  def foo(a, options: {})
    42
  end

  # +Demo#bar+ -> Integer
  #
  # Method documentation.
  #
  # @param [Boolean] verbose Param documentation.
  # @return [Integer]
  def bar(verbose: true)
    123
  end

  private

  # +Demo.bump+ -> Symbol
  #
  # Method documentation.
  #
  # @return [Symbol]
  def self.bump
    :ok
  end

  class << self
    private

    # +Demo.internal+ -> Object
    #
    # Method documentation.
    #
    # @private
    # @return [Object]
    def internal; end
  end
end
```

> [!NOTE]
> - The tool inserts doc headers at the start of def/defs lines and preserves everything else.
> - Class methods show with a dot (`+Demo.bump+`, `+Demo.internal+`).
> - Methods inside `class << self` under private are marked `@private`.

## CLI

```shell
docscribe [options] [files...]
```

Docscribe operates in one of three modes:

- **STDIN mode** (`--stdin`): read Ruby source from STDIN and print rewritten source to STDOUT.
- **Check mode** (`--dry` / `--check`): dry-run for files; exits `1` if any file would change (useful in CI).
- **Write mode** (`--write`): rewrite files in place.

If you pass no files (and don’t use `--stdin`), Docscribe exits with an error.

Options:

- `--stdin` Read source from STDIN and print with docs inserted.
- `--write` Rewrite files in place.
- `--check`, `--dry` Dry-run: exit 1 if any file would change (useful in CI).
- `--refresh` Regenerate docs: replace existing doc blocks above methods.
- `--rbs` Use RBS signatures for `@param`/`@return` when available (falls back to inference).
- `--sig-dir DIR` Add an RBS signature directory (repeatable). Implies `--rbs`.
- `--include PATTERN` Include PATTERN (method id or file path; glob or /regex/).
- `--exclude PATTERN` Exclude PATTERN (method id or file path; glob or /regex/). Exclude wins.
- `--include-file PATTERN` Only process files matching PATTERN (glob or /regex/).
- `--exclude-file PATTERN` Skip files matching PATTERN (glob or /regex/). Exclude wins.
- `--config PATH` Path to config YAML (default: `docscribe.yml`).
- `--version` Print version and exit.
- `-h`, `--help` Show help.

Examples:

- Preview output for a single file (via STDIN):
  ```shell
  cat path/to/file.rb | docscribe --stdin
  ```

- Rewrite files in place (ensure a clean working tree):
  ```shell
  docscribe --write lib/**/*.rb
  ```

- CI check (fail if docs are missing/stale):
  ```shell
  docscribe --dry lib/**/*.rb
  ```

- Refresh docs (regenerate headers/tags and replace existing doc blocks):
  ```shell
  docscribe --write --refresh lib/**/*.rb
  ```

- Check a directory (Docscribe expands directories to `**/*.rb`):
  ```shell
  docscribe --dry lib
  ```

> [!TIP]
> `--dry --refresh` is a "refresh dry-run" — it tells you whether regenerating docs would change anything.

## Inline behavior

- Inserts comment blocks immediately above def/defs nodes.
- Skips methods that already have a comment directly above them (does not merge into existing comments) unless you pass
  `--refresh`.
- Maintains original formatting and constructs; only adds comments.

### Refresh mode

With `--refresh`, Docscribe removes the contiguous comment block immediately above a method (plus intervening blank
lines)
and replaces it with a fresh generated block.

Use with caution (prefer a clean working tree and review diffs).

### Output markers in CI

When using `--dry`, Docscribe prints one character per file:

- `.` = file is up-to-date
- `F` = file would change (missing/stale docs)

When using `--write`:

- `.` = file already OK
- `C` = file was corrected and rewritten

Docscribe prints a summary at the end and exits non-zero in `--dry` mode if any file would change.

## Parser backend (Parser gem vs Prism)

Docscribe internally works with `parser`-gem-compatible AST nodes and `Parser::Source::*` objects
(so it can use `Parser::Source::TreeRewriter` without changing formatting).

- On Ruby **<= 3.3**, Docscribe parses using the `parser` gem.
- On Ruby **>= 3.4**, Docscribe parses using **Prism** and translates the tree into the `parser` gem's AST.

You can force a backend with an environment variable:

```shell
DOCSCRIBE_PARSER_BACKEND=parser bundle exec docscribe --dry lib
DOCSCRIBE_PARSER_BACKEND=prism  bundle exec docscribe --dry lib
```

## RBS integration (optional)

Docscribe can use RBS signatures to improve `@param` and `@return` types.

CLI:

```shell
docscribe --rbs --sig-dir sig --write lib
```

Config:

```yaml
rbs:
  enabled: true
  sig_dirs: [ "sig" ]
  collapse_generics: false
```

> [!NOTE]
> If `collapse_generics` is set to `true`, Docscribe will simplify generic types from RBS:
> - `Hash<Symbol, Object>` -> `Hash`
> - `Array<String>` -> `Array`

> [!IMPORTANT]
> If you run Docscribe via Bundler (`bundle exec docscribe`), you may need to add `gem "rbs"` to your project's
> Gemfile (or use a Gemfile that includes it) so `require "rbs"` works reliably. If RBS can't be loaded, Docscribe falls
> back to inference.

## Type inference

Heuristics (best-effort).

Parameters:

- `*args` -> `Array`
- `**kwargs` -> `Hash`
- `&block` -> `Proc`
- keyword args:
    - verbose: `true` -> `Boolean`
    - options: `{}` -> `Hash`
    - kw: (no default) -> `Object`
- positional defaults:
    - `42` -> `Integer`, `1.0` -> `Float`, `'x'` -> `String`, `:ok` -> `Symbol`
    - `[]` -> `Array`, `{}` -> `Hash`, `/x/` -> `Regexp`, `true`/`false` -> `Boolean`, `nil` -> `nil`

Return values:

- For simple bodies, Docscribe looks at the last expression or explicit return.
- Unions with nil become optional types (e.g., `String` or `nil` -> `String?`).
- For control flow (`if`/`case`), it unifies branches conservatively.

## Rescue-aware returns and @raise

Docscribe detects exceptions and rescue branches:

- Rescue exceptions become `@raise` tags:
    - `rescue Foo, Bar` -> `@raise [Foo]` and `@raise [Bar]`
    - bare rescue -> `@raise [StandardError]`
    - explicit raise/fail also adds a tag (`raise Foo` -> `@raise [Foo]`, `raise` -> `@raise [StandardError]`)

- Conditional return types for rescue branches:
    - Docscribe adds `@return [Type] if ExceptionA, ExceptionB` for each rescue clause.

## Visibility semantics

We match Ruby's behavior:

- A bare `private`/`protected`/`public` in a class/module body affects instance methods only.
- Inside `class << self`, a bare visibility keyword affects class methods only.
- `def self.x` in a class body remains `public` unless `private_class_method` is used, or it's inside `class << self`
  under `private`.

Inline tags:

- `@private` is added for methods that are private in context.
- `@protected` is added similarly for protected methods.

> [!IMPORTANT]
> `module_function`: Docscribe documents methods affected by `module_function` as module methods (`M.foo`) rather than
> instance methods (`M#foo`), because that is usually the callable/public API. If a method was previously private as
> an instance method, Docscribe will avoid marking the generated docs as `@private` after it is promoted to a module
> method.

```ruby
module M
  private

  def foo; end

  module_function :foo
end
```

## API (library) usage

```ruby
require "docscribe/inline_rewriter"

code = <<~RUBY
  class Demo
    def foo(a, options: {}); 42; end
    class << self; private; def internal; end; end
  end
RUBY

# Insert docs (skip methods that already have a comment above)
out = Docscribe::InlineRewriter.insert_comments(code)
puts out

# Replace existing comment blocks above methods (equivalent to CLI --refresh)
out2 = Docscribe::InlineRewriter.insert_comments(code, rewrite: true)
```

## Configuration

Docscribe can be configured via a YAML file (`docscribe.yml` by default, or pass `--config PATH`).

### Filtering

Docscribe can filter both *files* and *methods*.

File filtering (recommended for excluding specs, vendor code, etc.):

```yaml
filter:
  files:
    exclude: [ "spec" ]
```

Method filtering matches method ids like:

- `MyModule::MyClass#instance_method`
- `MyModule::MyClass.class_method`

Example:

```yaml
filter:
  exclude:
    - "*#initialize"
```

CLI overrides are available too:

```shell
# Method filtering (matches method ids like A#foo / A.bar)
docscribe --dry --exclude '*#initialize' lib
docscribe --dry --include '/^MyModule::.*#(foo|bar)$/' lib

# File filtering (matches paths relative to the project root)
docscribe --dry --exclude-file 'spec' lib spec
docscribe --dry --exclude-file '/^spec\//' lib
```

> [!NOTE] `/regex/` passed to `--include`/`--exclude` is treated as a **method-id** pattern. Use `--include-file`
> `--exclude-file` for file regex filters.

### Attribute macros (`attr_*`)

Docscribe can generate YARD `@!attribute` directives above `attr_reader`, `attr_writer`, and `attr_accessor`.

Enable it:

```yaml
emit:
  attributes: true
```

Example:

```ruby
class User
  attr_reader :name

  private

  attr_accessor :token
end
```

Becomes:

```ruby
class User
  # @!attribute [r] name
  #   @return [Object]
  attr_reader :name

  private

  # @!attribute [rw] token
  # @private
  #   @return [Object]
  #   @param value [Object]
  attr_accessor :token
end
```

> [!NOTE]
> - Attribute docs are inserted above the attr_* call, not above generated methods (since they don’t exist as def
    nodes).
> - If RBS is enabled, Docscribe will try to use the RBS return type of the reader method as the attribute type.

### Create a starter config

Create `docscribe.yml` in the current directory:

```shell
docscribe init
```

Write to a custom path:

```shell
docscribe init --config config/docscribe.yml
```

Overwrite if it already exists:

```shell
docscribe init --force
```

Print the template to stdout:

```shell
docscribe init --stdout
```

## CI integration

Fail the build if files would change:

```yaml
- name: Check inline docs
  run: docscribe --dry lib/**/*.rb
```

Auto-fix before test stage:

```yaml
- name: Insert inline docs
  run: docscribe --write lib/**/*.rb
```

Refresh mode (regenerate existing method docs):

```yaml
- name: Refresh inline docs
  run: docscribe --write --refresh lib/**/*.rb
```

## Comparison to YARD's parser

Docscribe and YARD solve different parts of the documentation problem:

- Docscribe inserts/updates inline comments by rewriting source.
- YARD can generate HTML docs based on inline comments.

Recommended workflow:

- Use Docscribe to seed and maintain inline docs with inferred tags/types.
- Optionally use YARD (dev-only) to render HTML from those comments:
  ```shell
  yard doc -o docs
  ```

## Limitations

- **Does not** merge into existing comments; in normal mode, a method with a comment directly above it is skipped. Use
  `--refresh` to regenerate.
- Type inference is heuristic. Complex flows and meta-programming will fall back to `Object` or best-effort types.
- Inline rewrite is textual; ensure a clean working tree before using `--write` or `--refresh`.

## Roadmap

- Merge tags into existing docstrings (opt-in).
- Recognize common APIs for return inference (`Time.now`, `File.read`, `JSON.parse`).
- Configurable rules and per-project exclusions.
- Editor integration for on-save inline docs.

## Contributing

```shell
bundle exec rspec
bundle exec rubocop
```

## License

MIT
