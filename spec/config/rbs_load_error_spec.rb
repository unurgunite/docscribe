# frozen_string_literal: true

RSpec.describe Docscribe::Config do
  describe 'build_rbs_provider with missing rbs gem' do
    let(:config) { described_class.new({ 'rbs' => { 'enabled' => true } }) }

    before do
      allow(config).to receive(:require).and_call_original
      allow(config).to receive(:require).with('docscribe/types/rbs/provider').and_raise(LoadError)
    end

    it 'returns nil' do
      expect(config.rbs_provider).to be_nil
    end

    it 'warns to stderr' do
      expect { config.rbs_provider }
        .to output(/--rbs requires the `rbs` gem/).to_stderr
    end
  end

  describe 'build_core_rbs_provider with missing rbs gem' do
    let(:config) { described_class.new({}) }

    before do
      allow(config).to receive(:require).and_call_original
      allow(config).to receive(:require).with('docscribe/types/rbs/provider').and_raise(LoadError)
    end

    it 'returns nil' do
      expect(config.core_rbs_provider).to be_nil
    end

    it 'warns to stderr' do
      expect { config.core_rbs_provider }
        .to output(/--rbs requires the `rbs` gem/).to_stderr
    end
  end
end
