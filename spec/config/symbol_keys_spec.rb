# frozen_string_literal: true

RSpec.describe Docscribe::Config do
  describe 'keyword overrides' do
    it 'accepts symbol keys like string keys', :aggregate_failures do
      expect(described_class.new(validate_types: true).validate_types?).to be(true)
      expect(described_class.new('validate_types' => true).validate_types?).to be(true)
      expect(described_class.new(validate_types: false).validate_types?).to be(false)
      expect(described_class.new('validate_types' => false).validate_types?).to be(false)
    end

    it 'validates types by default' do
      expect(described_class.new.validate_types?).to be(true)
    end

    it 'keeps symbol overrides visible under the string key' do
      expect(described_class.new(validate_types: true).raw['validate_types']).to be(true)
    end

    it 'normalizes nested symbol keys' do
      config = described_class.new(rbs: { sig_dirs: ['sig'] }, filter: { files: { exclude: ['tmp'] } })

      expect(config.raw.dig('rbs', 'sig_dirs')).to eq(['sig'])
      expect(config.raw.dig('filter', 'files', 'exclude')).to eq(['tmp'])
    end

    it 'does not leave duplicate symbol keys behind' do
      config = described_class.new(validate_types: true)

      expect(config.raw.keys).to all(be_a(String))
      expect(config.raw.keys.size).to eq(described_class.new.raw.keys.size)
    end
  end
end
