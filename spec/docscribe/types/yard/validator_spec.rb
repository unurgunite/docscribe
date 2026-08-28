# frozen_string_literal: true

require 'docscribe/types/yard/validator'

RSpec.describe Docscribe::Types::Yard::Validator do
  def valid?(str)
    described_class.valid?(str)
  end

  def syntax_valid?(str)
    described_class.syntax_valid?(str)
  end

  describe '.valid?' do
    it 'returns false for nil' do
      expect(valid?(nil)).to be false
    end

    it 'returns false for empty string' do
      expect(valid?('')).to be false
      expect(valid?('   ')).to be false
    end

    it 'returns true for simple types' do
      expect(valid?('String')).to be true
      expect(valid?('Integer')).to be true
      expect(valid?('Symbol')).to be true
    end

    it 'returns false for leftover content like Sym bol' do
      expect(valid?('Sym bol')).to be false
    end

    it 'returns true for union with comma' do
      expect(valid?('String, Integer')).to be true
    end

    it 'returns false for double comma' do
      expect(valid?('String,, Integer')).to be false
    end

    it 'returns false for unbalanced brackets' do
      expect(valid?('Array<String')).to be false
      expect(valid?('Array<String>>')).to be false
    end

    it 'returns true for generic' do
      expect(valid?('Array<String>')).to be true
      expect(valid?('Hash<Symbol, Integer>')).to be true
    end

    it 'returns true for optional' do
      expect(valid?('String?')).to be true
    end

    it 'returns true for namespaced type' do
      expect(valid?('Foo::Bar')).to be true
    end
  end

  describe '.syntax_valid?' do
    it 'delegates to valid? with balanced check' do
      expect(syntax_valid?('String')).to be true
      expect(syntax_valid?('Sym bol')).to be false
      expect(syntax_valid?('Array<String>')).to be true
      expect(syntax_valid?('Array<String')).to be false
    end
  end

  describe '.balanced_brackets?' do
    it 'checks angle brackets' do
      expect(described_class.balanced_brackets?('Array<String>')).to be true
      expect(described_class.balanced_brackets?('Array<String')).to be false
    end

    it 'checks bracket' do
      expect(described_class.balanced_brackets?('a[b]')).to be true
      expect(described_class.balanced_brackets?('a[b')).to be false
    end
  end

  describe '.fully_consumed?' do
    it 'returns false for Sym bol' do
      expect(described_class.fully_consumed?('Sym bol')).to be false
    end

    it 'returns true for valid' do
      expect(described_class.fully_consumed?('Symbol')).to be true
    end
  end
end
