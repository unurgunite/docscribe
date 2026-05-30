# frozen_string_literal: true

RSpec.describe 'CollectorPlugin doc normalization' do
  after { Docscribe::Plugin::Registry.clear! }

  def build_plugin(anchor_type:, doc:)
    Class.new(Docscribe::Plugin::Base::CollectorPlugin) do
      def initialize(anchor_type:, doc:)
        super()
        @anchor_type = anchor_type
        @doc = doc
      end

      def collect(ast, _buffer)
        node = find_first(ast, @anchor_type)
        return [] unless node

        [{ anchor_node: node, doc: @doc }]
      end

      private

      def find_first(node, type)
        return nil unless node.respond_to?(:type)

        return node if node.type == type

        children = node.respond_to?(:children) ? node.children : []
        children.each do |child|
          next unless child.respond_to?(:type)

          found = find_first(child, type)
          return found if found
        end

        nil
      end
    end.new(anchor_type: anchor_type, doc: doc)
  end

  def find_first(node, type)
    return nil unless node.respond_to?(:type)

    return node if node.type == type

    children = node.respond_to?(:children) ? node.children : []
    children.each do |child|
      next unless child.respond_to?(:type)

      found = find_first(child, type)
      return found if found
    end

    nil
  end

  context 'when anchor_node is :def and plugin doc is tag-only' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) do
      Docscribe::Config.new(
        'emit' => { 'include_default_message' => true },
        'doc' => { 'default_message' => 'PLUGIN DEFAULT.' }
      )
    end

    let(:code) do
      <<~RUBY
        class A
          def foo
            1
          end
        end
      RUBY
    end

    before do
      plugin = build_plugin(anchor_type: :def, doc: "# @return [Boolean]\n")
      Docscribe::Plugin::Registry.register(plugin)
    end

    it 'prepends configured default message before tag-only plugin docs' do
      expect(out).to include('# PLUGIN DEFAULT.')
      expect(out).to include('# @return [Boolean]')

      msg_idx = out.index('# PLUGIN DEFAULT.')
      tag_idx = out.index('# @return [Boolean]')
      def_idx = out.index("def foo\n")

      expect(msg_idx).not_to be_nil
      expect(tag_idx).not_to be_nil
      expect(def_idx).not_to be_nil

      expect(msg_idx).to be < tag_idx
      expect(tag_idx).to be < def_idx
    end
  end

  context 'when include_default_message is false' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) do
      Docscribe::Config.new(
        'emit' => { 'include_default_message' => false },
        'doc' => { 'default_message' => 'PLUGIN DEFAULT.' }
      )
    end

    let(:code) do
      <<~RUBY
        class A
          def foo
            1
          end
        end
      RUBY
    end

    before do
      plugin = build_plugin(anchor_type: :def, doc: "# @return [Boolean]\n")
      Docscribe::Plugin::Registry.register(plugin)
    end

    it 'does not prepend default message' do
      expect(out).not_to include('# PLUGIN DEFAULT.')
      expect(out).to include('# @return [Boolean]')
    end
  end

  context 'when plugin doc already contains prose' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) do
      Docscribe::Config.new(
        'emit' => { 'include_default_message' => true },
        'doc' => { 'default_message' => 'PLUGIN DEFAULT.' }
      )
    end

    let(:code) do
      <<~RUBY
        class A
          def foo
            1
          end
        end
      RUBY
    end

    before do
      plugin = build_plugin(
        anchor_type: :def,
        doc: "# Custom prose line.\n# @return [Boolean]\n"
      )
      Docscribe::Plugin::Registry.register(plugin)
    end

    it 'does not prepend default message when plugin doc has prose' do
      expect(out).to include('# Custom prose line.')
      expect(out).to include('# @return [Boolean]')
      expect(out).not_to include('# PLUGIN DEFAULT.')
    end
  end

  context 'when anchor_node is :defs (class method)' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) do
      Docscribe::Config.new(
        'emit' => { 'include_default_message' => true },
        'doc' => { 'default_message' => 'PLUGIN DEFAULT.' }
      )
    end

    let(:code) do
      <<~RUBY
        class A
          def self.foo
            1
          end
        end
      RUBY
    end

    before do
      plugin = build_plugin(anchor_type: :defs, doc: "# @return [Boolean]\n")
      Docscribe::Plugin::Registry.register(plugin)
    end

    it 'prepends default message for tag-only docs on :defs as well' do
      expect(out).to include('# PLUGIN DEFAULT.')
      expect(out).to include('# @return [Boolean]')
      expect(out).to include('def self.foo')
    end
  end

  context 'when anchor_node is not a method (:send)' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) do
      Docscribe::Config.new(
        'emit' => { 'include_default_message' => true },
        'doc' => { 'default_message' => 'PLUGIN DEFAULT.' }
      )
    end

    let(:code) do
      <<~RUBY
        class A
          has_many :posts
        end
      RUBY
    end

    before do
      plugin = build_plugin(anchor_type: :send, doc: "# @return [Boolean]\n")
      Docscribe::Plugin::Registry.register(plugin)
    end

    it 'does not prepend default message for non-def anchors' do
      expect(out).to include('# @return [Boolean]')
      expect(out).not_to include('# PLUGIN DEFAULT.')
    end
  end

  context 'when plugin doc ends with whitespace-only lines' do
    subject(:out) { inline(code, config: conf, strategy: :safe) }

    let(:conf) do
      Docscribe::Config.new(
        'emit' => { 'include_default_message' => false }
      )
    end

    let(:code) do
      <<~RUBY
        class A
          def foo
            1
          end
        end
      RUBY
    end

    before do
      plugin = build_plugin(anchor_type: :def, doc: "# @return [Boolean]\n\n\n")
      Docscribe::Plugin::Registry.register(plugin)
    end

    it 'trims trailing whitespace-only lines (no extra empty lines before def)' do
      expect(out).to include("# @return [Boolean]\n  def foo")
    end
  end
end
