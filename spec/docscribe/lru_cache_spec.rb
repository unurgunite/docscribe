# frozen_string_literal: true

require 'docscribe/lru_cache'

RSpec.describe Docscribe::LRUCache do
  subject(:cache) { described_class.new(max_size) }

  let(:max_size) { 3 }

  describe '#[] and #[]=' do
    it 'stores and retrieves values' do
      cache[:a] = 1
      expect(cache[:a]).to eq(1)
    end

    it 'returns nil for missing keys' do
      expect(cache[:missing]).to be_nil
    end

    describe 'access order promotion' do
      before do
        cache[:a] = 1
        cache[:b] = 2
        cache[:c] = 3
        cache[:a] # promote :a
        cache[:d] = 4
      end

      it 'evicts least recently used after read' do
        expect(cache[:b]).to be_nil
      end

      it 'keeps :a after promotion' do
        expect(cache[:a]).to eq(1)
      end

      it 'keeps :c as recently used' do
        expect(cache[:c]).to eq(3)
      end

      it 'stores the new entry' do
        expect(cache[:d]).to eq(4)
      end
    end
  end

  describe '#size' do
    it 'tracks number of entries' do
      cache[:a] = 1
      cache[:b] = 2
      expect(cache.size).to eq(2)
    end

    it 'does not exceed max_size' do
      max_size.times { |i| cache[i] = i }
      cache[:extra] = 99
      expect(cache.size).to eq(max_size)
    end
  end

  describe '#clear' do
    it 'empties the cache' do
      cache[:a] = 1
      cache.clear
      expect(cache).to be_empty
    end
  end

  describe '#empty?' do
    it 'returns true when empty' do
      expect(cache).to be_empty
    end

    it 'returns false with entries' do
      cache[:a] = 1
      expect(cache).not_to be_empty
    end
  end

  describe 'eviction policy' do
    before do
      cache[:a] = 1
      cache[:b] = 2
      cache[:c] = 3
    end

    it 'evicts least recently used entries' do
      cache[:a] # access :a, now LRU is :b
      cache[:d] = 4
      expect(cache[:b]).to be_nil
    end

    it 'retains :a after access' do
      cache[:a] # access :a, now LRU is :b
      cache[:d] = 4
      expect(cache[:a]).to eq(1)
    end

    it 'retains :c as survivor' do
      cache[:a] # access :a, now LRU is :b
      cache[:d] = 4
      expect(cache[:c]).to eq(3)
    end

    it 'stores the new entry' do
      cache[:a] # access :a, now LRU is :b
      cache[:d] = 4
      expect(cache[:d]).to eq(4)
    end

    describe 'reinsertion on write' do
      before do
        cache[:a] = 10 # should move :a to front
        cache[:d] = 4
      end

      it 'evicts the previous LRU' do
        expect(cache[:b]).to be_nil
      end

      it 'keeps updated value' do
        expect(cache[:a]).to eq(10)
      end
    end
  end
end
