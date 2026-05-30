# SchemaAttributes Plugin

Generates YARD documentation for ActiveRecord database columns by parsing `db/schema.rb`.

## What it does

When docscribe processes model files, this plugin reads the Rails schema and generates `@!attribute` doc blocks with the
correct column types:

```ruby
# Before docscribe:
class User < ApplicationRecord
  def admin?
    is_admin
  end
end

# After docscribe (with this plugin):
# @!attribute [r] email
#   @return [String]
#
# @!attribute [r] is_admin
#   @return [Boolean]
#
class User < ApplicationRecord
  def admin?
    is_admin
  end
end
```

## Installation

### 1. Add to docscribe.yml

```yaml
plugins:
  require:
    - ./examples/plugins/collector_plugin/schema_attributes/plugin
```

And register it

```ruby
require 'examples/plugins/collector_plugin/schema_attributes/plugin'

Docscribe::Plugin::Registry.register(DocscribePlugins::SchemaAttributes.new)
```

## Supported column types

| schema.rb type | YARD type    |
|----------------|--------------|
| `boolean`      | `Boolean`    |
| `integer`      | `Integer`    |
| `bigint`       | `Integer`    |
| `float`        | `Float`      |
| `decimal`      | `BigDecimal` |
| `string`       | `String`     |
| `text`         | `String`     |
| `binary`       | `String`     |
| `datetime`     | `Time`       |
| `date`         | `Date`       |
| `time`         | `Time`       |
| `timestamp`    | `Time`       |
| `json`         | `Hash`       |
| `jsonb`        | `Hash`       |
| `inet`         | `IPAddr`     |
| `uuid`         | `String`     |
| `citext`       | `String`     |
| `hstore`       | `Hash`       |
| `enum`         | `String`     |

## Skipped columns

Standard Rails columns are skipped: `id`, `created_at`, `updated_at`, `deleted_at`.

## Requirements

- `parser` gem (already a docscribe dependency)
- Rails project with `db/schema.rb`
