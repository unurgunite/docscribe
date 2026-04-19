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

- [`rails_associations/`](collector_plugin) — `RailsAssociations`: documents
  ActiveRecord association macros (`belongs_to`, `has_many`, `has_one`,
  `has_and_belongs_to_many`).

## Choosing the right plugin type

Use **TagPlugin** when you want to append one or more tags to methods that
Docscribe already collects (`def` / `def self.`). The plugin receives a
snapshot of the method and returns `Array<Docscribe::Plugin::Tag>`.

Use **CollectorPlugin** when you need to document constructs that are not
`def` nodes — DSL macros, `define_method`, association helpers, and so on.
The plugin receives the raw AST and source buffer and returns insertion
targets directly.

> [!IMPORTANT]
> Do not use a CollectorPlugin to re-document ordinary `def` methods.
> Both the standard Collector and the plugin would fire independently,
> producing two doc blocks for the same method. Use TagPlugin or config
> filters instead.
