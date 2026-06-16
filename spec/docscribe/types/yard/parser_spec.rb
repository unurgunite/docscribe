# frozen_string_literal: true

require 'docscribe/types/yard/parser'
require 'docscribe/types/yard/formatter'

RSpec.describe Docscribe::Types::Yard do
  def parse(string)
    Docscribe::Types::Yard.parse(string)
  end

  def to_rbs(node)
    Docscribe::Types::Yard::Formatter.to_rbs(node)
  end

  describe '.parse' do
    it 'returns nil for nil' do
      expect(parse(nil)).to be_nil
    end

    it 'returns nil for empty string' do
      expect(parse('')).to be_nil
    end

    it 'returns nil for whitespace' do
      expect(parse('   ')).to be_nil
    end

    it 'parses a simple named type' do
      node = parse('String')
      expect(node).to be_a(Docscribe::Types::Yard::Named)
      expect(node.name).to eq('String')
    end

    it 'parses namespaced type' do
      node = parse('Foo::Bar')
      expect(node).to be_a(Docscribe::Types::Yard::Named)
      expect(node.name).to eq('Foo::Bar')
    end

    it 'parses Boolean as named' do
      node = parse('Boolean')
      expect(node).to be_a(Docscribe::Types::Yard::Named)
    end

    it 'parses void as literal' do
      node = parse('void')
      expect(node).to be_a(Docscribe::Types::Yard::Literal)
      expect(node.value).to eq('void')
    end

    it 'parses nil as literal' do
      node = parse('nil')
      expect(node).to be_a(Docscribe::Types::Yard::Literal)
      expect(node.value).to eq('nil')
    end

    it 'parses self as literal' do
      node = parse('self')
      expect(node).to be_a(Docscribe::Types::Yard::Literal)
      expect(node.value).to eq('self')
    end

    it 'parses generic Array<String>' do
      node = parse('Array<String>')
      expect(node).to be_a(Docscribe::Types::Yard::Generic)
      expect(node.base).to eq('Array')
      expect(node.args.size).to eq(1)
      expect(node.args.first).to be_a(Docscribe::Types::Yard::Named)
      expect(node.args.first.name).to eq('String')
    end

    it 'parses generic with union arg' do
      node = parse('Hash<String, Integer>')
      expect(node).to be_a(Docscribe::Types::Yard::Generic)
      expect(node.base).to eq('Hash')
      expect(node.args.size).to eq(1)
      expect(node.args.first).to be_a(Docscribe::Types::Yard::Union)
    end

    it 'parses generic with nested generics' do
      node = parse('Array<Array<String>>')
      expect(node).to be_a(Docscribe::Types::Yard::Generic)
      expect(node.base).to eq('Array')
      inner = node.args.first
      expect(inner).to be_a(Docscribe::Types::Yard::Generic)
      expect(inner.base).to eq('Array')
      expect(inner.args.first.name).to eq('String')
    end

    it 'parses hash map syntax' do
      node = parse('Hash{String => Integer}')
      expect(node).to be_a(Docscribe::Types::Yard::HashMap)
      expect(node.key_type.name).to eq('String')
      expect(node.value_type.name).to eq('Integer')
    end

    it 'parses bare hash map' do
      node = parse('{String => Integer}')
      expect(node).to be_a(Docscribe::Types::Yard::HashMap)
      expect(node.key_type.name).to eq('String')
      expect(node.value_type.name).to eq('Integer')
    end

    it 'parses union with comma' do
      node = parse('String, Integer')
      expect(node).to be_a(Docscribe::Types::Yard::Union)
      expect(node.types.size).to eq(2)
    end

    it 'parses union with three types' do
      node = parse('String, Integer, nil')
      expect(node).to be_a(Docscribe::Types::Yard::Union)
      expect(node.types.size).to eq(3)
    end

    it 'parses optional' do
      node = parse('String?')
      expect(node).to be_a(Docscribe::Types::Yard::Optional)
      expect(node.type).to be_a(Docscribe::Types::Yard::Named)
      expect(node.type.name).to eq('String')
    end

    it 'parses tuple' do
      node = parse('(String, Integer)')
      expect(node).to be_a(Docscribe::Types::Yard::Tuple)
      expect(node.types.size).to eq(2)
      expect(node.types[0].name).to eq('String')
      expect(node.types[1].name).to eq('Integer')
    end

    it 'parses intersection' do
      node = parse('String & Integer')
      expect(node).to be_a(Docscribe::Types::Yard::Intersection)
      expect(node.types.size).to eq(2)
    end

    it 'parses duck type' do
      node = parse('#foo')
      expect(node).to be_a(Docscribe::Types::Yard::Duck)
      expect(node.method_names).to eq(%w[foo])
    end
  end

  describe 'Formatter.to_rbs' do
    it 'converts String' do
      expect(to_rbs(parse('String'))).to eq('String')
    end

    it 'converts Integer' do
      expect(to_rbs(parse('Integer'))).to eq('Integer')
    end

    it 'converts Boolean to bool' do
      expect(to_rbs(parse('Boolean'))).to eq('bool')
    end

    it 'converts Object to untyped' do
      expect(to_rbs(parse('Object'))).to eq('untyped')
    end

    it 'converts void' do
      expect(to_rbs(parse('void'))).to eq('void')
    end

    it 'converts nil' do
      expect(to_rbs(parse('nil'))).to eq('nil')
    end

    it 'converts self' do
      expect(to_rbs(parse('self'))).to eq('self')
    end

    it 'converts Array<String>' do
      expect(to_rbs(parse('Array<String>'))).to eq('Array[String]')
    end

    it 'converts Hash{String => Integer}' do
      expect(to_rbs(parse('Hash{String => Integer}'))).to eq('Hash[String, Integer]')
    end

    it 'converts Hash{Symbol => Object}' do
      expect(to_rbs(parse('Hash{Symbol => Object}'))).to eq('Hash[Symbol, untyped]')
    end

    it 'converts union' do
      expect(to_rbs(parse('String, Integer'))).to eq('String | Integer')
    end

    it 'converts optional' do
      expect(to_rbs(parse('String?'))).to eq('String?')
    end

    it 'converts tuple' do
      expect(to_rbs(parse('(String, Integer)'))).to eq('[String, Integer]')
    end

    it 'converts intersection' do
      expect(to_rbs(parse('String & Integer'))).to eq('String & Integer')
    end

    it 'converts nested generic with hash map' do
      expect(to_rbs(parse('Array<Hash{String => Integer}>'))).to eq('Array[Hash[String, Integer]]')
    end

    it 'converts nil to untyped' do
      expect(to_rbs(nil)).to eq('untyped')
    end
  end
end
