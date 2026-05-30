# Docscribe plugin examples

This directory contains example plugins demonstrating the two extension
points provided by Docscribe's plugin system.

* [Docscribe plugin examples](#docscribe-plugin-examples)
    * [Extension points](#extension-points)
    * [TagPlugin examples](#tagplugin-examples)
    * [CollectorPlugin examples](#collectorplugin-examples)
    * [Choosing the right plugin type](#choosing-the-right-plugin-type)

## Extension points

| Type                                         | Purpose                                                          |
|----------------------------------------------|------------------------------------------------------------------|
| [TagPlugin](#tagplugin-examples)             | Append extra YARD tags to already-collected methods              |
| [CollectorPlugin](#collectorplugin-examples) | Document non-standard DSL constructs by walking the AST directly |

## TagPlugin examples

- [`tag_plugin/`](tag_plugin) — `ApiTagPlugin`: appends `@api public` /
  `@api private` to every method based on its Ruby visibility.

## CollectorPlugin examples

- [`rails_associations/`](collector_plugin/rails_associations) — `RailsAssociations`:
  documents ActiveRecord association macros (`belongs_to`, `has_many`, `has_one`,
  `has_and_belongs_to_many`).

- [`schema_attributes/`](collector_plugin/schema_attributes) — `SchemaAttributes`:
  generates `@!attribute` blocks with correct column types by parsing `db/schema.rb`.

- [`model_attributes/`](collector_plugin/model_attributes) — `ModelAttributes`:
  generates accurate `@return` types for ActiveRecord model methods by reading
  `db/schema.rb` or `db/structure.sql`.

## Choosing the right plugin type

Use **TagPlugin** when you want to append one or more tags to methods that Docscribe already
collects (`def` / `def self.`). The plugin receives a snapshot of the method
and returns `Array<Docscribe::Plugin::Tag>`.

Use **CollectorPlugin** when you need to document constructs that are not
`def` nodes — DSL macros, `define_method`, association helpers, and so on.
The plugin receives the raw AST and source buffer and returns insertion
targets directly.

> [!NOTE]
> A `CollectorPlugin` **can** target ordinary `def` methods to override the standard collector's output.
> When a plugin and the standard collector both insert docs at the same source position, the plugin takes priority and
> the standard collector's insertion is dropped.
>
> If multiple `CollectorPlugins` target the same source position, `Registry.register(plugin, priority: N)` (default `0`)
> controls which one wins: the highest priority plugin(s) are kept (ties are kept).
> - only the highest-priority plugin insertion(s) are kept (ties are kept)
> - multiple insertions from the winning plugin(s) at that position are preserved (e.g. `SchemaAttributes` may generate
    several `@!attribute` blocks at one anchor point)
