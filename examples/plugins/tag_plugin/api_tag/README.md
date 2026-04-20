# ApiTagPlugin

A minimal **TagPlugin** example that appends an `@api` visibility tag to
every method documented by Docscribe.

- Public methods -> `@api public`
- Protected / private methods -> `@api private`

This mirrors the `@api` convention used by many YARD-documented Ruby gems
(e.g. Rails itself).

* [ApiTagPlugin](#apitagplugin)
    * [Usage](#usage)
    * [Example](#example)
    * [Idempotency](#idempotency)
    * [Extending this example](#extending-this-example)

## Usage

Register the plugin in `docscribe_plugins.rb`:

```ruby
require_relative 'examples/plugins/tag_plugin/plugin'

Docscribe::Plugin::Registry.register(DocscribePlugins::ApiTagPlugin.new)
```

Add the file to `docscribe.yml`:

```yaml
plugins:
  require:
    - ./docscribe_plugins
```

## Example

Input:

```ruby
class OrderService
  def create(params)
    Order.create!(params)
  end

  private

  def validate(params)
    params.fetch(:amount)
  end
end
```

Output after `docscribe -a lib`:

```ruby
class OrderService
  # +OrderService#create+ -> Order
  #
  # Method documentation.
  #
  # @param [Object] params Param documentation.
  # @return [Order]
  # @api public
  def create(params)
    Order.create!(params)
  end

  private

  # +OrderService#validate+ -> Object
  #
  # Method documentation.
  #
  # @private
  # @param [Object] params Param documentation.
  # @return [Object]
  # @api private
  def validate(params)
    params.fetch(:amount)
  end
end
```

## Idempotency

Docscribe checks whether a tag with the same name already exists in the
doc block before appending. Running `docscribe -a` twice produces the same
output — `@api` will not be duplicated.

## Extending this example

You can make the plugin conditional — for example, only tag public methods,
or only tag methods in specific containers:

```ruby
def call(context)
  return [] unless context.scope == :instance
  return [] unless context.visibility == :public

  [Docscribe::Plugin::Tag.new(name: 'api', text: 'public')]
end
```

Or add richer metadata using the `types:` field:

```ruby
Docscribe::Plugin::Tag.new(name: 'raise', types: ['ArgumentError'], text: 'if params is invalid')
```
