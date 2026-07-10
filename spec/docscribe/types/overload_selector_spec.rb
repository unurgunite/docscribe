# frozen_string_literal: true

require 'docscribe/types/overload_selector'

Sig = Struct.new(:positional_types, :return_type, :rest_positional, :param_types, keyword_init: true)

RSpec.describe Docscribe::Types::OverloadSelector do
  describe '.select' do
    it 'returns nil for nil overloads' do
      expect(described_class.select(nil, arg_count: 0)).to be_nil
    end

    it 'returns nil for empty overloads' do
      expect(described_class.select([], arg_count: 0)).to be_nil
    end

    it 'returns the only overload when size is 1' do
      sig = Sig.new
      expect(described_class.select([sig], arg_count: 0)).to be(sig)
    end

    it 'picks overload with matching positional arg count' do
      sig_a = Sig.new(positional_types: %w[String])
      sig_b = Sig.new(positional_types: %w[String Integer])
      expect(described_class.select([sig_a, sig_b], arg_count: 2)).to be(sig_b)
    end

    it 'prefers overload with matching return type' do
      sig_no_ret = Sig.new(positional_types: %w[String])
      sig_with_ret = Sig.new(positional_types: %w[String], return_type: 'Integer')
      expect(described_class.select([sig_no_ret, sig_with_ret], arg_count: 1)).to be(sig_with_ret)
    end

    it 'prefers overload with specific return type over Object' do
      sig_obj = Sig.new(positional_types: %w[String], return_type: 'Object')
      sig_str = Sig.new(positional_types: %w[String], return_type: 'String')
      expect(described_class.select([sig_obj, sig_str], arg_count: 1)).to be(sig_str)
    end

    it 'prefers overload with matching param names' do
      sig_no_p = Sig.new(positional_types: %w[String], param_types: {})
      sig_with_p = Sig.new(positional_types: %w[String], param_types: { 'name' => 'String' })
      result = described_class.select([sig_no_p, sig_with_p], arg_count: 1, param_names: %w[name])
      expect(result).to be(sig_with_p)
    end

    it 'favors overload with rest_positional when arg_count exceeds positional types' do
      sig_rest = Sig.new(positional_types: %w[String], rest_positional: true)
      sig_exact = Sig.new(positional_types: %w[String Integer])
      expect(described_class.select([sig_rest, sig_exact], arg_count: 2)).to be(sig_exact)
    end

    it 'falls back to first overload when no matching signature' do
      first = Sig.new(positional_types: %w[String], return_type: 'Integer')
      second = Sig.new(positional_types: [])
      expect(described_class.select([first, second], arg_count: 2)).to be(first)
    end

    it 'returns first overload when no candidate exceeds arg_count' do
      sig = Sig.new(positional_types: %w[String Integer])
      expect(described_class.select([sig], arg_count: 0)).to be(sig)
    end
  end
end
