# Rails associations

An example plugin that documents ActiveRecord associations (`belongs_to`, `has_many`, `has_one`,
`has_and_belongs_to_many`) is available in [`examples/plugins/rails_associations/`]().

Given:

```ruby
class Post < ApplicationRecord
  belongs_to :user
  has_many :comments
end
```

The plugin generates:

```ruby
class Post < ApplicationRecord
  # @!attribute [r] user
  #   Associated User object.
  #
  # @return [ApplicationRecord]
  belongs_to :user

  # @!attribute [r] comments
  #   Returns the associated comments.
  #
  #   @return [Array<Comment**>]
  has_many :comments
end
```

To use it, register the plugin in `docscribe_plugins.rb`:

```ruby
require_relative 'examples/plugins/rails_associations/plugin'

Docscribe::Plugin::Registry.register(DocscribePlugins::RailsAssociations::Plugin.new)
```
