# frozen_string_literal: true

require 'docscribe/plugin'

RSpec.describe Docscribe::Plugin::Registry do
  after { described_class.clear! }

  describe '.register' do
    context 'with a TagPlugin subclass' do
      let(:plugin) { Class.new(Docscribe::Plugin::Base::TagPlugin).new }

      before { described_class.register(plugin) }

      it { expect(described_class.tag_plugins).to include(plugin) }
      it { expect(described_class.collector_plugins).to be_empty }
    end

    context 'with a CollectorPlugin subclass' do
      let(:plugin) { Class.new(Docscribe::Plugin::Base::CollectorPlugin).new }

      before { described_class.register(plugin) }

      it { expect(described_class.collector_plugins).to include(plugin) }
      it { expect(described_class.tag_plugins).to be_empty }

      it 'stores default priority (0)', :aggregate_failures do
        entry = described_class.collector_entries.first
        expect(entry.plugin).to eq(plugin)
        expect(entry.priority).to eq(0)
      end

      it 'stores explicit priority', :aggregate_failures do
        plugin2 = Class.new(Docscribe::Plugin::Base::CollectorPlugin).new
        described_class.register(plugin2, priority: 7)
        expect(described_class.collector_entries.last.plugin).to eq(plugin2)
        expect(described_class.collector_entries.last.priority).to eq(7)
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
      let(:plugin) do
        obj = Object.new
        def obj.collect(_ast, _buffer)
          []
        end
        obj
      end

      before { described_class.register(plugin) }

      it { expect(described_class.collector_plugins).to include(plugin) }
    end

    context 'with an unsupported object' do
      it 'raises ArgumentError' do
        expect { described_class.register(Object.new) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.all / .tag_plugins / .collector_plugins' do
    it 'returns copies so external mutations do not affect the registry' do
      rogue = instance_double(Docscribe::Plugin::Base::TagPlugin, call: [])
      described_class.tag_plugins << rogue
      expect(described_class.tag_plugins).to be_empty
    end
  end

  describe '.clear!' do
    before do
      described_class.register(->(_ctx) { [] })
      described_class.register(Class.new(Docscribe::Plugin::Base::CollectorPlugin).new)
      described_class.clear!
    end

    it { expect(described_class.tag_plugins).to be_empty }
    it { expect(described_class.collector_plugins).to be_empty }
  end
end
