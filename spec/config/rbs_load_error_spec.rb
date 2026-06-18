# frozen_string_literal: true

RSpec.describe Docscribe::Config do
  before do
    skip_unless_rbs_available!
    skip 'RBS requires Ruby 3.0+' if RUBY_VERSION < '3.0'

    allow(config).to receive(:require).and_call_original
    allow(config).to receive(:require).with('docscribe/types/rbs/provider').and_raise(LoadError)
  end

  describe 'build_rbs_provider with missing rbs gem' do
    let(:config) { described_class.new({ 'rbs' => { 'enabled' => true } }) }

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

    it 'returns nil without warning' do
      expect(config.core_rbs_provider).to be_nil
    end

    it 'does not warn to stderr' do
      expect { config.core_rbs_provider }
        .not_to output.to_stderr
    end
  end
end
