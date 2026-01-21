# Docscribe

[![Gem Version](https://img.shields.io/gem/v/docscribe.svg)](https://rubygems.org/gems/docscribe)
[![RubyGems Downloads](https://img.shields.io/gem/dt/docscribe.svg)](https://rubygems.org/gems/docscribe)
[![CI](https://github.com/unurgunite/docscribe/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/unurgunite/docscribe/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/unurgunite/docscribe.svg)](https://github.com/unurgunite/docscribe/blob/master/LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.7-blue.svg)](#installation)

Generate inline, YARD-style documentation comments for Ruby methods by analyzing your code's AST.

Docscribe inserts doc headers before method definitions, infers parameter and return types (including rescue-aware
returns), and respects Ruby visibility semantics — without using YARD to parse.

- No AST reprinting. Your original code, formatting, and constructs (like `class << self`, `heredocs`, `%i[]`) are
  preserved.
- Inline-first. Comments are inserted at the start of each `def`/`defs` line.
- Heuristic type inference for params and return values, including conditional returns in rescue branches.
- Optional rewrite mode for regenerating existing method docs.
- Ruby 3.4+ syntax supported using Prism translation (see "Parser backend" below).

Why not YARD? We started with YARD's parser, but switched to an AST-based in-place rewriter for maximum preservation of
source structure and exact control over Ruby semantics.

* [Docscribe](#docscribe)
    * [Installation](#installation)
    * [Quick start](#quick-start)
    * [CLI](#cli)
    * [Inline behavior](#inline-behavior)
        * [Rewrite mode](#rewrite-mode)
        * [Output markers in CI](#output-markers-in-ci)
    * [Parser backend (Parser gem vs Prism)](#parser-backend-parser-gem-vs-prism)
    * [Type inference](#type-inference)
    * [Rescue-aware returns and @raise](#rescue-aware-returns-and-raise)
    * [Visibility semantics](#visibility-semantics)
    * [API (library) usage](#api-library-usage)
    * [Configuration](#configuration)
        * [CLI](#cli-1)
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
gem 'docscribe'
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

Notes:

- The tool inserts doc headers at the start of def/defs lines and preserves everything else.
- Class methods show with a dot (`+Demo.bump+`, `+Demo.internal+`).
- Methods inside `class << self` under private are marked `@private.`

## CLI

```shell
docscribe [options] [files...]
```

Options:

- `--stdin` Read source from STDIN and print with docs inserted.
- `--write` Rewrite files in place.
- `--check`, `--dry` Dry-run: exit 1 if any file would change (useful in CI).
- `--refresh` Replace any existing comment block above methods (see "Rewrite mode" below).
- `--include PATTERN` Only process methods matching PATTERN (glob or /regex/).
- `--exclude PATTERN` Skip methods matching PATTERN (glob or /regex/). Exclude wins.
- `--include-file PATTERN` Only process files matching PATTERN (glob or /regex/).
- `--exclude-file PATTERN` Skip files matching PATTERN (glob or /regex/). Exclude wins.
- `--config PATH` Path to config YAML (default: `docscribe.yml`).
- `--version` Print version and exit.
- `-h`, `--help` Show help.

Examples:

- Print to stdout for one file:
  ```shell
  docscribe path/to/file.rb
  ```
- Rewrite files in place (ensure a clean working tree):
  ```shell
  docscribe --write lib/**/*.rb
  ```
- CI check (fail if docs are missing/stale):
  ```shell
  docscribe --dry lib/**/*.rb
  ```
- Rewrite existing doc blocks above methods (regenerate headers/tags):
  ```shell
  docscribe --refresh --write lib/**/*.rb
  ```
- Check a directory (Docscribe expands directories to `**/*.rb`):
  ```shell
  docscribe --dry lib
  ```

Tip: `--dry --refresh` is a "refresh dry-run" — it tells you whether regenerating docs would change anything (useful
after changing config or upgrading Docscribe).

## Inline behavior

- Inserts comment blocks immediately above def/defs nodes.
- Skips methods that already have a comment directly above them (does not merge into existing comments) unless you pass
  `--refresh`.
- Maintains original formatting and constructs; only adds comments.

### Rewrite mode

- With `--refresh`, Docscribe will remove the contiguous comment block immediately above a method (plus intervening
  blank
  lines) and replace it with a fresh generated block.
- This is useful to refresh docs across a codebase after improving inference or rules.
- Use with caution (prefer a clean working tree and review diffs).

### Output markers in CI

When using `--dry`, Docscribe prints one character per file:

- `.` = file is up-to-date
- `F` = file would change (missing/stale docs)

When using `--write`:

- `.` = file already OK
- `C` = file was corrected and rewritten

Docscribe prints a summary at the end and exits non-zero in `--dry` mode if any file would change.

## Parser backend (Parser gem vs Prism)

Docscribe internally works with `parser`-gem-compatible AST nodes and `Parser::Source::*` objects (so it can use
`Parser::Source::TreeRewriter` without changing your formatting).

- On Ruby **<= 3.3**, Docscribe parses using the `parser` gem.
- On Ruby **>= 3.4**, Docscribe parses using **Prism** and translates the tree into the `parser` gem’s AST (so tooling
  stays compatible).

You can force a backend with an environment variable:

```shell
DOCSCRIBE_PARSER_BACKEND=parser bundle exec docscribe --dry lib
DOCSCRIBE_PARSER_BACKEND=prism  bundle exec docscribe --dry lib
```

## Type inference

Heuristics (best-effort):

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

- For simple bodies, Docscribe looks at the last expression or explicit return:
    - `42` -> `Integer`
    - `:ok` -> `Symbol`
    - Unions with nil become optional types (e.g., `String` or `nil` -> `String?`).
- For control flow (`if`/`case`), it unifies branches conservatively.

## Rescue-aware returns and @raise

Docscribe detects exceptions and rescue branches:

- Rescue exceptions become `@raise` tags:
    - `rescue Foo, Bar` -> `@raise [Foo]` and `@raise [Bar]`
    - bare rescue -> `@raise [StandardError]`
    - (optional) explicit raise/fail also adds a tag (`raise Foo` -> `@raise [Foo]`, `raise` ->
      `@raise [StandardError]`).

- Conditional return types for rescue branches:
    - Docscribe adds `@return [Type]` if `ExceptionA`, `ExceptionB` for each rescue clause.

Example:

```ruby

class X
  def a
    42
  rescue Foo, Bar
    "fallback"
  end

  def b
    risky
  rescue
    "n"
  end
end
```

Becomes:

```ruby

class X
  # +X#a+ -> Integer
  #
  # Method documentation.
  #
  # @raise [Foo]
  # @raise [Bar]
  # @return [Integer]
  # @return [String] if Foo, Bar
  def a
    42
  rescue Foo, Bar
    "fallback"
  end

  # +X#b+ -> Object
  #
  # Method documentation.
  #
  # @raise [StandardError]
  # @return [Object]
  # @return [String] if StandardError
  def b
    risky
  rescue
    "n"
  end
end
```

## Visibility semantics

We match Ruby's behavior:

- A bare `private`/`protected`/`public` in a class/module body affects instance methods only.
- Inside `class << self`, a bare visibility keyword affects class methods only.
- `def self.x` in a class body remains `public` unless `private_class_method` is used, or it's inside `class << self`
  under `private`.

Inline tags:

- `@private` is added for methods that are private in context.
- `@protected` is added similarly for protected methods.

## API (library) usage

```ruby
require 'docscribe/inline_rewriter'

code = <<~RUBY
  class Demo
    def foo(a, options: {}); 42; end
    class << self; private; def internal; end; end
  end
RUBY

# Insert docs (skip methods that already have a comment above)
out = Docscribe::InlineRewriter.insert_comments(code)
puts out

# Replace existing comment blocks above methods
out2 = Docscribe::InlineRewriter.insert_comments(code, rewrite: true)
```

## Configuration

Docscribe can be configured via a YAML file (docscribe.yml by default, or pass --config PATH).

Example:

```yaml
emit:
  header: true           # controls "# +Class#method+ -> Type"
  param_tags: true       # include @param lines
  return_tag: true       # include normal @return
  visibility_tags: true  # include @private/@protected
  raise_tags: true       # include @raise [Error]
  rescue_conditional_returns: true  # include "@return [...] if Exception"

doc:
  default_message: "Method documentation."

methods:
  instance:
    public:
      return_tag: true
      default_message: "Public API. Please document purpose and params."
  class:
    private:
      return_tag: false

inference:
  fallback_type: "Object"
  nil_as_optional: true
  treat_options_keyword_as_hash: true
```

- emit.* toggles control which tags are emitted globally.
- methods.<scope>.<visibility> allows per-method overrides:
    - return_tag: true/false
    - default_message: override the message for that bucket
- inference.* tunes type inference defaults.

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
docscribe --dry --exclude '*#initialize' lib
docscribe --dry --exclude-file 'spec' lib spec
```

### CLI

```shell
docscribe --config docscribe.yml --write lib/**/*.rb
```

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

Print the template to stdout (no file written):

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

Rewrite mode (regenerate existing method docs):

```yaml
- name: Refresh inline docs
  run: docscribe --refresh --write lib/**/*.rb
```

## Comparison to YARD's parser

Docscribe and YARD solve different parts of the documentation problem:

- Parsing and insertion:
    - Docscribe parses with Ruby's AST (parser gem) and inserts/updates doc comments inline. It does not reformat code
      or produce HTML by itself.
    - YARD parses Ruby into a registry and can generate documentation sites and perform advanced analysis (tags,
      transitive docs, macros).

- Preservation vs generation:
    - Docscribe preserves your original source exactly, only inserting comment blocks above methods.
    - YARD generates documentation output (HTML, JSON) based on its registry; it's not designed to write back to your
      source.

- Semantics:
    - Docscribe models Ruby visibility semantics precisely for inline usage (including `class << self`).
    - YARD has rich semantics around tags and directives; it can leverage your inline comments (including those inserted
      by Docscribe).

- Recommended workflow:
    - Use Docscribe to seed and maintain inline docs with inferred tags/types.
    - Optionally use YARD (dev-only) to render HTML from those comments:
      ```shell
      yard doc -o docs
      ```

## Limitations

- Does not merge into existing comments; in normal mode, a method with a comment directly above it is skipped. Use
  `--refresh` to regenerate.
- Type inference is heuristic. Complex flows and meta-programming will fall back to Object or best-effort types.
- Ruby 2.7+ supported.
- Inline rewrite is textual; ensure a clean working tree before using `--write` or `--refresh`.

## Roadmap

- Merge tags into existing docstrings (opt-in).
- Recognize common APIs for return inference (`Time.now`, `File.read`, `JSON.parse`).
- Configurable rules and per-project exclusions.
- Editor integration for on-save inline docs.

## Contributing

Issues and PRs welcome. Please run:

```shell
bundle exec rspec
bundle exec rubocop
```

See CODE_OF_CONDUCT.md.

## License

MIT
