# ModelAttributes Plugin

Generates accurate `@return` documentation for ActiveRecord model methods by consulting `db/schema.rb` or
`db/structure.sql` for column types.

## What it does

Instead of generating generic `@!attribute` blocks, this plugin analyzes method bodies and generates precise `@return`
types based on database column types.

### Example

```ruby
# Before docscribe:
class User < ApplicationRecord
  def admin?
    is_admin
  end

  def age_restriction?
    age < 21
  end

  def fullname
    name + surname
  end
end

# After docscribe (with this plugin):
class User < ApplicationRecord
  # @return [Boolean]
  def admin?
    is_admin
  end

  # @return [Boolean]
  def age_restriction?
    age < 21
  end

  # @return [String]
  def fullname
    name + surname
  end
end
```

## How it works

1. **Parser** (`schema_parser.rb`) reads `db/schema.rb` or `db/structure.sql` and maps table columns to database types
2. **Plugin** (`plugin.rb`) analyzes model file methods:
    - Walks the AST to find method definitions
    - For each method, analyzes the return expression
    - Looks up column types from the parser
    - Infers YARD types from column types (e.g., `boolean` -> `Boolean`, `integer` -> `Integer`)
    - Generates `@return` doc blocks

## Column type mapping

| schema.rb / SQL type            | YARD type           |
|---------------------------------|---------------------|
| `boolean` / `bool`              | `Boolean`           |
| `integer` / `bigint` / `serial` | `Integer`           |
| `float` / `double`              | `Float`             |
| `decimal` / `numeric`           | `BigDecimal`        |
| `string` / `varchar` / `text`   | `String`            |
| `datetime` / `timestamp`        | `Time`              |
| `date`                          | `Date`              |
| `json` / `jsonb`                | `Hash`              |
| `uuid` / `inet`                 | `String` / `IPAddr` |

## Skipped columns

Standard Rails columns are skipped: `id`, `created_at`, `updated_at`, `deleted_at`.

## Installation

Copy these files into your project (example layout):

```
lib/docscribe_model_attributes/
  plugin.rb
  schema_parser/
    schema_parser.rb
    schema_rb_parser.rb
    structure_sql_parser.rb
```

Then require/register it (example `docscribe_plugins.rb`):

```ruby
require_relative 'lib/docscribe_model_attributes/plugin'

# Higher number => higher priority. Recommended to set this high if you have other
# CollectorPlugins that might also target method anchors.
Docscribe::Plugin::Registry.register(
  DocscribePlugins::ModelAttributes.new(root: Dir.pwd),
  priority: 10
)
```

And reference `docscribe_plugins.rb` from `docscribe.yml`:

```yaml
plugins:
  require:
    - ./docscribe_plugins
```

## Supported formats

- **`db/schema.rb`**: Full parsing of Rails schema DSL
- **`db/structure.sql`**: Partial parsing of PostgreSQL/MySQL DDL (CREATE TABLE statements)

## Limitations

- Only supports `db/schema.rb` and `db/structure.sql` — not custom schema paths
- Column type detection is heuristic-based (regex parsing of SQL)
- Method body analysis covers common Ruby patterns (`<`, `==`, `+`, `.length`, etc.)
- Does not handle complex method chains or dynamic attribute access

## License

MIT — same as docscribe.
