# frozen_string_literal: true

require 'docscribe/plugin'

RSpec.describe Docscribe::Plugin::Registry do
  after { described_class.clear! }

  describe '.register' do
    context 'with a TagPlugin subclass' do
      it 'adds to tag_plugins' do
        plugin = Class.new(Docscribe::Plugin::Base::TagPlugin).new
        described_class.register(plugin)
        expect(described_class.tag_plugins).to include(plugin)
        expect(described_class.collector_plugins).to be_empty
      end
    end

    context 'with a CollectorPlugin subclass' do
      it 'adds to collector_plugins' do
        plugin = Class.new(Docscribe::Plugin::Base::CollectorPlugin).new
        described_class.register(plugin)
        expect(described_class.collector_plugins).to include(plugin)
        expect(described_class.tag_plugins).to be_empty
      end
    end

    context 'with a duck-typed tag plugin (responds to #call)' do
      it 'adds to tag_plugins' do
        plugin = ->(_ctx) { [] }
        described_class.register(plugin)
        expect(described_class.tag_plugins).to include(plugin)
      end
    end

    context 'with a duck-typed collector plugin (responds to #collect)' do
      it 'adds to collector_plugins' do
        plugin = Object.new
        def plugin.collect(_ast, _buffer)
          []
        end
        described_class.register(plugin)
        expect(described_class.collector_plugins).to include(plugin)
      end
    end

    context 'with an unsupported object' do
      it 'raises ArgumentError' do
        expect { described_class.register(Object.new) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.all / .tag_plugins / .collector_plugins' do
    it 'returns copies so external mutations do not affect the registry' do
      described_class.tag_plugins << double('rogue')
      expect(described_class.tag_plugins).to be_empty
    end
  end

  describe '.clear!' do
    it 'removes all plugins from both lists' do
      described_class.register(->(_ctx) { [] })
      described_class.register(Class.new(Docscribe::Plugin::Base::CollectorPlugin).new)
      described_class.clear!
      expect(described_class.tag_plugins).to be_empty
      expect(described_class.collector_plugins).to be_empty
    end
  end
end
