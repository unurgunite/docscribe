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
- Inline-first. Comments are inserted before method headers without reprinting the AST. For methods with a leading
  Sorbet `sig`, new docs are inserted above the first `sig`.
- Heuristic type inference for params and return values, including conditional returns in rescue branches.
- Safe and aggressive update modes:
    - safe mode inserts missing docs, merges existing doc-like blocks, and normalizes sortable tags
    - aggressive mode rebuilds existing doc blocks
- Ruby 3.4+ syntax supported using Prism translation (see "Parser backend" below).
- Optional external type integrations:
    - RBS via `--rbs` / `--sig-dir`
    - Sorbet via inline `sig` declarations and RBI files with `--sorbet` / `--rbi-dir`
- Optional `attr_reader`/`attr_writer`/`attr_accessor` documentation via YARD `@!attribute` (see Configuration).

Common workflows:

- Inspect what safe doc updates would be applied:
  `docscribe lib`

- Apply safe doc updates:
  `docscribe -a lib`

- Apply aggressive doc updates:
  `docscribe -A lib`

- Use RBS signatures when available:
  `docscribe -a --rbs --sig-dir sig lib`

- Use Sorbet signatures when available: `docscribe -a --sorbet --rbi-dir sorbet/rbi lib`

## Contents

* [Docscribe](#docscribe)
    * [Contents](#contents)
    * [Installation](#installation)
    * [Quick start](#quick-start)
    * [CLI](#cli)
        * [Options](#options)
        * [Examples](#examples)
    * [Update strategies](#update-strategies)
        * [Safe strategy](#safe-strategy)
        * [Aggressive strategy](#aggressive-strategy)
        * [Output markers](#output-markers)
    * [Parser backend (Parser gem vs Prism)](#parser-backend-parser-gem-vs-prism)
    * [External type integrations (optional)](#external-type-integrations-optional)
        * [RBS](#rbs)
        * [Sorbet](#sorbet)
        * [Inline Sorbet example](#inline-sorbet-example)
        * [Sorbet RBI example](#sorbet-rbi-example)
        * [Sorbet comment placement](#sorbet-comment-placement)
        * [Generic type formatting](#generic-type-formatting)
        * [Notes and fallback behavior](#notes-and-fallback-behavior)
    * [Type inference](#type-inference)
    * [Rescue-aware returns and @raise](#rescue-aware-returns-and-raise)
    * [Visibility semantics](#visibility-semantics)
    * [API (library) usage](#api-library-usage)
    * [Configuration](#configuration)
        * [Filtering](#filtering)
        * [Attribute macros (`attr_*`)](#attribute-macros-attr_)
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
> - The tool inserts doc headers before method headers and preserves everything else.
> - For methods with a leading Sorbet `sig`, docs are inserted above the first `sig`.
> - Class methods show with a dot (`+Demo.bump+`, `+Demo.internal+`).
> - Methods inside `class << self` under `private` are marked `@private`.

## CLI

```shell
docscribe [options] [files...]
```

Docscribe has three main ways to run:

- **Inspect mode** (default): checks what safe doc updates would be applied and exits non-zero if files need changes.
- **Safe autocorrect** (`-a`, `--autocorrect`): writes safe, non-destructive updates in place.
- **Aggressive autocorrect** (`-A`, `--autocorrect-all`): rewrites existing doc blocks more aggressively.
- **STDIN mode** (`--stdin`): reads Ruby source from STDIN and prints rewritten source to STDOUT.

If you pass no files and don’t use `--stdin`, Docscribe processes the current directory recursively.

### Options

- `-a`, `--autocorrect`  
  Apply safe doc updates in place.

- `-A`, `--autocorrect-all`  
  Apply aggressive doc updates in place.

- `--stdin`  
  Read source from STDIN and print rewritten output.

- `--verbose`  
  Print per-file actions.

- `--explain`  
  Show detailed reasons for each file that would change.

- `--rbs`  
  Use RBS signatures for `@param`/`@return` when available (falls back to inference).

- `--sig-dir DIR`  
  Add an RBS signature directory (repeatable). Implies `--rbs`.

- `--include PATTERN`  
  Include PATTERN (method id or file path; glob or `/regex/`).

- `--exclude PATTERN`  
  Exclude PATTERN (method id or file path; glob or `/regex/`). Exclude wins.

- `--include-file PATTERN`  
  Only process files matching PATTERN (glob or `/regex/`).

- `--exclude-file PATTERN`  
  Skip files matching PATTERN (glob or `/regex/`). Exclude wins.

- `-C`, `--config PATH`  
  Path to config YAML (default: `docscribe.yml`).

- `-v`, `--version`  
  Print version and exit.

- `-h`, `--help`  
  Show help.

### Examples

- Inspect a directory:
  ```shell
  docscribe lib
  ```

- Apply safe updates:
  ```shell
  docscribe -a lib/**/*.rb
  ```

- Apply aggressive updates:
  ```shell
  docscribe -A lib/**/*.rb
  ```

- Preview output for a single file via STDIN:
  ```shell
  cat path/to/file.rb | docscribe --stdin
  ```

- Use RBS signatures:
  ```shell
  docscribe -a --rbs --sig-dir sig lib
  ```

- Show detailed reasons for files that would change:
  ```shell
  docscribe --verbose --explain lib
  ```

## Update strategies

Docscribe supports two update strategies: **safe** and **aggressive**.

### Safe strategy

Used by:

- default inspect mode: `docscribe lib`
- safe write mode: `docscribe -a lib`

Safe strategy:

- inserts docs for undocumented methods
- merges missing tags into existing **doc-like** blocks
- normalizes configurable tag order inside sortable tag runs
- preserves existing prose and comments where possible

This is the recommended day-to-day mode.

### Aggressive strategy

Used by:

- aggressive write mode: `docscribe -A lib`

Aggressive strategy:

- rebuilds existing doc blocks
- replaces existing generated documentation more fully
- is more invasive than safe mode

Use it when you want to rebaseline or regenerate docs wholesale.

### Output markers

In inspect mode, Docscribe prints one character per file:

- `.` = file is up to date
- `F` = file would change
- `E` = file had an error

In write modes:

- `.` = file already OK
- `C` = file was updated
- `E` = file had an error

With `--verbose`, Docscribe prints per-file statuses instead.

With `--explain`, Docscribe also prints detailed reasons, such as:

- missing `@param`
- missing `@return`
- missing module_function note
- unsorted tags

## Parser backend (Parser gem vs Prism)

Docscribe internally works with `parser`-gem-compatible AST nodes and `Parser::Source::*` objects (so it can use
`Parser::Source::TreeRewriter` without changing formatting).

- On Ruby **<= 3.3**, Docscribe parses using the `parser` gem.
- On Ruby **>= 3.4**, Docscribe parses using **Prism** and translates the tree into the `parser` gem's AST.

You can force a backend with an environment variable:

```shell
DOCSCRIBE_PARSER_BACKEND=parser bundle exec docscribe lib
DOCSCRIBE_PARSER_BACKEND=prism  bundle exec docscribe lib
```

## External type integrations (optional)

Docscribe can improve generated `@param` and `@return` types by reading external signatures instead of relying only on
AST inference.

> [!IMPORTANT]
> When external type information is available, Docscribe resolves signatures in this order:
> - inline Sorbet `sig` declarations in the current Ruby source;
> - Sorbet RBI files;
> - RBS files;
> - AST inference fallback.
>
> If an external signature cannot be loaded or parsed, Docscribe falls back to normal inference instead of failing.

### RBS

Docscribe can read method signatures from `.rbs` files and use them to generate more accurate parameter and return
types.

CLI:

```shell
docscribe -a --rbs --sig-dir sig lib
```

You can pass `--sig-dir` multiple times:

```shell
docscribe -a --rbs --sig-dir sig --sig-dir vendor/sigs lib
```

Config:

```yaml
rbs:
  enabled: true
  sig_dirs:
    - sig
  collapse_generics: false
```

Example:

```ruby
# Ruby source
class Demo
  def foo(verbose:, count:)
    "body says String"
  end
end
```

```ruby.rbs
# sig/demo.rbs
class Demo
    def foo: (verbose: bool, count: Integer) -> Integer
end
```

Generated docs will prefer the RBS signature over inferred Ruby types:

```ruby

class Demo
  # +Demo#foo+ -> Integer
  #
  # Method documentation.
  #
  # @param [Boolean] verbose Param documentation.
  # @param [Integer] count Param documentation.
  # @return [Integer]
  def foo(verbose:, count:)
    'body says String'
  end
end
```

### Sorbet

Docscribe can also read Sorbet signatures from:

- inline `sig` declarations in Ruby source
- RBI files

CLI:

```shell
docscribe -a --sorbet lib
```

With RBI directories:

```shell
docscribe -a --sorbet --rbi-dir sorbet/rbi lib
```

You can pass `--rbi-dir` multiple times:

```shell
docscribe -a --sorbet --rbi-dir sorbet/rbi --rbi-dir rbi lib
```

Config:

```yaml
sorbet:
  enabled: true
  rbi_dirs:
    - sorbet/rbi
    - rbi
  collapse_generics: false
```

### Inline Sorbet example

```ruby

class Demo
  extend T::Sig

  sig { params(verbose: T::Boolean, count: Integer).returns(Integer) }
  def foo(verbose:, count:)
    'body says String'
  end
end
```

Docscribe will use the Sorbet signature instead of the inferred body type:

```ruby

class Demo
  extend T::Sig

  # +Demo#foo+ -> Integer
  #
  # Method documentation.
  #
  # @param [Boolean] verbose Param documentation.
  # @param [Integer] count Param documentation.
  # @return [Integer]
  sig { params(verbose: T::Boolean, count: Integer).returns(Integer) }
  def foo(verbose:, count:)
    'body says String'
  end
end
```

### Sorbet RBI example

```ruby
# Ruby source
class Demo
  def foo(verbose:, count:)
    'body says String'
  end
end
```

```ruby
# sorbet/rbi/demo.rbi
class Demo
  extend T::Sig

  sig { params(verbose: T::Boolean, count: Integer).returns(Integer) }
  def foo(verbose:, count:); end
end
```

With:

```shell
docscribe -a --sorbet --rbi-dir sorbet/rbi lib
```

Docscribe will use the RBI signature for generated docs.

### Sorbet comment placement

For methods with a leading Sorbet `sig`, Docscribe treats the signature as part of the method header.

That means:

- new docs are inserted **above the first `sig`**
- existing docs **above the `sig`** are recognized and merged
- existing legacy docs **between `sig` and `def`** are also recognized

Example input:

```ruby
# demo.rb
class Demo
  extend T::Sig

  sig { returns(Integer) }
  def foo
    1
  end
end
```

Example output:

```ruby
# demo.rb
class Demo
  extend T::Sig

  # +Demo#foo+ -> Integer
  #
  # Method documentation.
  #
  # @return [Integer]
  sig { returns(Integer) }
  def foo
    1
  end
end
```

### Generic type formatting

Both RBS and Sorbet integrations support `collapse_generics`.

When disabled:

```yaml
rbs:
  collapse_generics: false

sorbet:
  collapse_generics: false
```

Docscribe preserves generic container details where possible, for example:

- `Array<String>`
- `Hash<Symbol, Integer>`

When enabled:

```yaml
rbs:
  collapse_generics: true

sorbet:
  collapse_generics: true
```

Docscribe simplifies container types to their outer names, for example:

- `Array`
- `Hash`

### Notes and fallback behavior

- External signature support is the **best effort**.
- If a signature source cannot be loaded or parsed, Docscribe falls back to AST inference.
- RBS and Sorbet integrations are used only to improve generated types; Docscribe still rewrites Ruby source directly.
- Sorbet support does not require changing your documentation style — it only improves generated `@param` and `@return`
  tags when signatures are available.

## Type inference

Heuristics (best-effort).

Parameters:

- `*args` -> `Array`
- `**kwargs` -> `Hash`
- `&block` -> `Proc`
- keyword args:
    - `verbose: true` -> `Boolean`
    - `options: {}` -> `Hash`
    - `kw:` (no default) -> `Object`
- positional defaults:
    - `42` -> `Integer`, `1.0` -> `Float`, `'x'` -> `String`, `:ok` -> `Symbol`
    - `[]` -> `Array`, `{}` -> `Hash`, `/x/` -> `Regexp`, `true`/`false` -> `Boolean`, `nil` -> `nil`

Return values:

- For simple bodies, Docscribe looks at the last expression or explicit `return`.
- Unions with `nil` become optional types (e.g. `String` or `nil` -> `String?`).
- For control flow (`if`/`case`), it unifies branches conservatively.

## Rescue-aware returns and @raise

Docscribe detects exceptions and rescue branches:

- Rescue exceptions become `@raise` tags:
    - `rescue Foo, Bar` -> `@raise [Foo]` and `@raise [Bar]`
    - bare rescue -> `@raise [StandardError]`
    - explicit `raise`/`fail` also adds a tag (`raise Foo` -> `@raise [Foo]`, `raise` -> `@raise [StandardError]`)

- Conditional return types for rescue branches:
    - Docscribe adds `@return [Type] if ExceptionA, ExceptionB` for each rescue clause

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
> instance methods (`M#foo`), because that is usually the callable/public API. If a method was previously private as an
> instance method, Docscribe will avoid marking the generated docs as `@private` after it is promoted to a module
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

# Basic insertion behavior
out = Docscribe::InlineRewriter.insert_comments(code)
puts out

# Safe merge / normalization of existing doc-like blocks
out2 = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)

# Aggressive rebuild of existing doc blocks (similar to CLI -A)
out3 = Docscribe::InlineRewriter.insert_comments(code, strategy: :aggressive)
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
docscribe --exclude '*#initialize' lib
docscribe --include '/^MyModule::.*#(foo|bar)$/' lib

# File filtering (matches paths relative to the project root)
docscribe --exclude-file 'spec' lib spec
docscribe --exclude-file '/^spec\//' lib
```

> [!NOTE]
> `/regex/` passed to `--include`/`--exclude` is treated as a **method-id** pattern. Use `--include-file` /
`--exclude-file` for file regex filters.

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
> - Attribute docs are inserted above the `attr_*` call, not above generated methods (since they don’t exist as `def`
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

Fail the build if files would need safe updates:

```yaml
- name: Check inline docs
  run: docscribe lib/**/*.rb
```

Apply safe fixes before the test stage:

```yaml
- name: Apply safe inline docs
  run: docscribe -a lib/**/*.rb
```

Aggressively rebuild docs:

```yaml
- name: Rebuild inline docs
  run: docscribe -A lib/**/*.rb
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

- Safe mode only merges into existing **doc-like** comment blocks. Ordinary comments that are not recognized as
  documentation are preserved and treated conservatively.
- Type inference is heuristic. Complex flows and meta-programming will fall back to `Object` or best-effort types.
- Aggressive mode (`-A`) replaces existing doc blocks and should be reviewed carefully.

## Roadmap

- Recognize more common APIs for return inference (`Time.now`, `File.read`, `JSON.parse`).
- More configurable generation and formatting rules.
- Editor integration for on-save inline docs.
- Internal strategy API cleanup.

## Contributing

```shell
bundle exec rspec
bundle exec rubocop
```

## License

MIT
