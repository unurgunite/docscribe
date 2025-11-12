# Stingray Docs

Generate inline, YARD-style documentation comments for Ruby methods by analyzing your code’s AST. Stingray Docs inserts
doc headers before method definitions, infers parameter and return types, and respects Ruby visibility semantics —
without using YARD to parse.

- No AST reprinting. Your original code, formatting, and constructs (like class << self, heredocs, %i[]) are preserved.
- Inline-only by default. Comments are inserted surgically at the start of each def/defs line.
- Heuristic type inference for params and return values.

Why not YARD? We started with YARD’s parser, but switched to an AST-based in-place rewriter for maximum preservation of
source structure and control over visibility semantics.

## Table of Contents

* [Stingray Docs](#stingray-docs)
    * [Table of Contents](#table-of-contents)
    * [Installation](#installation)
    * [Quick start](#quick-start)
    * [CLI](#cli)
    * [Inline behavior](#inline-behavior)
    * [Type inference](#type-inference)
    * [Visibility semantics](#visibility-semantics)
    * [API (library) usage](#api-library-usage)
    * [CI integration](#ci-integration)
    * [Limitations](#limitations)
    * [Roadmap](#roadmap)
    * [Contributing](#contributing)
    * [License](#license)

## Installation

Add to your Gemfile:

```ruby
gem 'stingray_docs'
```

Then:

```bash
bundle install
```

Or install globally:

```bash
gem install stingray_docs
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

```bash
echo "…code above…" | stingray_docs --stdin
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
- Class methods show with a dot (+Demo.bump+, +Demo.internal+).
- internal inside class << self under private is marked @private.

## CLI

```bash
stingray_docs [options] [files...]
```

Options:

- --stdin Read source from STDIN and print with docs inserted.
- --write Rewrite files in place (inline mode).
- --check Dry-run: exit 1 if any file would change (useful in CI).
- --debug Enable debug logs (DEBUG_INLINE=1).
- --version Print version and exit.
- -h, --help Show help.

Examples:

- Print to stdout for one file:
  ```bash
  stingray_docs path/to/file.rb
  ```
- Rewrite files in place (make sure you have a clean working tree):
  ```bash
  stingray_docs --write lib/**/*.rb
  ```
- CI check (fail if docs are missing):
  ```bash
  stingray_docs --check lib/**/*.rb
  ```

## Inline behavior

- Inserts comment blocks immediately above def/defs nodes.
- Skips methods that already have a comment directly above them (does not merge into existing comments).
- Maintains original formatting and constructs; only adds comments.

## Type inference

Heuristics (best-effort):

Parameters:

- *args → Array
- **kwargs → Hash
- &block → Proc
- keyword args:
    - verbose: true → Boolean
    - options: {} → Hash
    - kw: (no default) → Object
- positional defaults:
    - 42 → Integer, 1.0 → Float, 'x'/'x' → String, :ok → Symbol
    - [] → Array, {} → Hash, /x/ → Regexp, true/false → Boolean, nil → nil

Return values:

- For simple bodies, the tool looks at the last expression or explicit return:
    - 42 → Integer
    - :ok → Symbol
    - nil unions become optional types, e.g., String or nil → String?
- For control flow (if/case), it unifies branches conservatively.

You can extend this in the future (e.g., Time.now → Time, File.read → String).

## Visibility semantics

We match Ruby’s behavior:

- A bare private/protected/public in a class/module body affects instance methods only.
- Inside class << self, a bare visibility keyword affects class methods only.
- def self.x in a class body remains public unless private_class_method is used or it’s inside class << self under
  private.

Inline rewriter tags:

- @private is added for methods that are private in context.
- @protected is added similarly for protected methods.

## API (library) usage

```ruby
require 'stingray_docs_internal/inline_rewriter'

code = <<~RUBY
  class Demo
    def foo(a, options: {}); 42; end
    class << self; private; def internal; end; end
  end
RUBY

out = StingrayDocsInternal::InlineRewriter.insert_comments(code)
puts out
```

Enable debug logs:

```ruby
ENV['DEBUG_INLINE'] = '1'
out = StingrayDocsInternal::InlineRewriter.insert_comments(code)
```

## CI integration

Fail the build if files would change:

```yaml
- name: Check docs inline
  run: stingray_docs --check lib/**/*.rb
```

Auto-fix before test stage:

```yaml
- name: Insert docs inline
  run: stingray_docs --write lib/**/*.rb
```

## Limitations

- Does not merge into existing comments; if a method already has a comment directly above it, the tool leaves it alone.
- Type inference is heuristic. Complex flows and meta-programming will fall back to Object.
- Only Ruby 2.7+ is officially supported.
- Inline rewrite is textual; ensure a clean working tree before using --write.

## Roadmap

- Merge tags into existing docstrings (opt-in).
- Recognize common APIs for return inference (Time.now, File.read, JSON.parse).
- Configurable rules and exclusions.
- Editor integration for on-save inline docs.

## Contributing

- Issues and PRs welcome.
- Please run:
  ```bash
  bundle exec rspec
  bundle exec rubocop
  ```
- See CODE_OF_CONDUCT.md.

## License

MIT
