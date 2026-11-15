# frozen_string_literal: true

require 'docscribe/types/yard/repair'

RSpec.describe Docscribe::Types::Yard::Repair do
  describe '.repair' do
    it 'joins a split constant name' do
      expect(described_class.repair('Sym bol')).to eq('Symbol')
    end

    it 'repairs each name inside a generic' do
      expect(described_class.repair('Hash<Sym bol, Int eger>')).to eq('Hash<Symbol,Integer>')
    end

    it 'repairs nested generics' do
      expect(described_class.repair('Hash<Str ing, Array<Int eger>>')).to eq('Hash<String,Array<Integer>>')
    end

    it 'leaves a valid type alone' do
      expect(described_class.repair('Array<String>')).to eq('Array<String>')
    end

    it 'declines when the squeezed name is not a known type' do
      expect(described_class.repair('Foo bar')).to be_nil
    end

    it 'declines on a blank type' do
      expect(described_class.repair('')).to be_nil
    end

    it 'declines on nil' do
      expect(described_class.repair(nil)).to be_nil
    end
  end
end
