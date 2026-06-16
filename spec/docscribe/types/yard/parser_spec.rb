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
      aggregate_failures do
        node = parse('String')
        expect(node).to be_a(Docscribe::Types::Yard::Named)
        expect(node.name).to eq('String')
      end
    end

    it 'parses namespaced type' do
      aggregate_failures do
        node = parse('Foo::Bar')
        expect(node).to be_a(Docscribe::Types::Yard::Named)
        expect(node.name).to eq('Foo::Bar')
      end
    end

    it 'parses Boolean as named' do
      node = parse('Boolean')
      expect(node).to be_a(Docscribe::Types::Yard::Named)
    end

    it 'parses void as literal' do
      aggregate_failures do
        node = parse('void')
        expect(node).to be_a(Docscribe::Types::Yard::Literal)
        expect(node.value).to eq('void')
      end
    end

    it 'parses nil as literal' do
      aggregate_failures do
        node = parse('nil')
        expect(node).to be_a(Docscribe::Types::Yard::Literal)
        expect(node.value).to eq('nil')
      end
    end

    it 'parses self as literal' do
      aggregate_failures do
        node = parse('self')
        expect(node).to be_a(Docscribe::Types::Yard::Literal)
        expect(node.value).to eq('self')
      end
    end

    it 'parses generic Array<String>' do
      aggregate_failures do
        node = parse('Array<String>')
        expect(node).to be_a(Docscribe::Types::Yard::Generic).and have_attributes(base: 'Array')
        expect(node.args.first).to be_a(Docscribe::Types::Yard::Named).and have_attributes(name: 'String')
      end
    end

    it 'parses generic with multiple args' do
      aggregate_failures do
        node = parse('Hash<Symbol, Object>')
        expect(node).to be_a(Docscribe::Types::Yard::Generic).and have_attributes(base: 'Hash')
        expect(node.args.size).to eq(2)
        expect(node.args[0]).to be_a(Docscribe::Types::Yard::Named).and have_attributes(name: 'Symbol')
        expect(node.args[1]).to be_a(Docscribe::Types::Yard::Named).and have_attributes(name: 'Object')
      end
    end

    it 'parses generic arg with union' do
      aggregate_failures do
        node = parse('Hash<String | Integer, Object>')
        expect(node).to be_a(Docscribe::Types::Yard::Generic).and have_attributes(base: 'Hash')
        expect(node.args.size).to eq(2)
        expect(node.args[0]).to be_a(Docscribe::Types::Yard::Union)
        expect(node.args[0].types.map(&:name)).to eq(%w[String Integer])
      end
    end

    it 'parses generic with nested generics' do
      aggregate_failures do
        node = parse('Array<Array<String>>')
        expect(node).to be_a(Docscribe::Types::Yard::Generic).and have_attributes(base: 'Array')
        expect(node.args.first.args.first.name).to eq('String')
      end
    end

    it 'parses hash map syntax' do
      aggregate_failures do
        node = parse('Hash{String => Integer}')
        expect(node).to be_a(Docscribe::Types::Yard::HashMap)
        expect([node.key_type.name, node.value_type.name]).to eq(%w[String Integer])
      end
    end

    it 'parses bare hash map' do
      aggregate_failures do
        node = parse('{String => Integer}')
        expect(node).to be_a(Docscribe::Types::Yard::HashMap)
        expect([node.key_type.name, node.value_type.name]).to eq(%w[String Integer])
      end
    end

    it 'parses union with comma' do
      aggregate_failures do
        node = parse('String, Integer')
        expect(node).to be_a(Docscribe::Types::Yard::Union)
        expect(node.types.size).to eq(2)
      end
    end

    it 'parses union with three types' do
      aggregate_failures do
        node = parse('String, Integer, nil')
        expect(node).to be_a(Docscribe::Types::Yard::Union)
        expect(node.types.size).to eq(3)
      end
    end

    it 'parses optional' do
      aggregate_failures do
        node = parse('String?')
        expect(node).to be_a(Docscribe::Types::Yard::Optional)
        expect(node.type).to be_a(Docscribe::Types::Yard::Named).and have_attributes(name: 'String')
      end
    end

    it 'parses tuple' do
      aggregate_failures do
        node = parse('(String, Integer)')
        expect(node).to be_a(Docscribe::Types::Yard::Tuple)
        expect(node.types).to match([have_attributes(name: 'String'), have_attributes(name: 'Integer')])
      end
    end

    it 'parses intersection' do
      aggregate_failures do
        node = parse('String & Integer')
        expect(node).to be_a(Docscribe::Types::Yard::Intersection)
        expect(node.types.size).to eq(2)
      end
    end

    it 'parses duck type' do
      aggregate_failures do
        node = parse('#foo')
        expect(node).to be_a(Docscribe::Types::Yard::Duck)
        expect(node.method_names).to eq(%w[foo])
      end
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

    it 'converts Hash<Symbol, Object>' do
      expect(to_rbs(parse('Hash<Symbol, Object>'))).to eq('Hash[Symbol, untyped]')
    end

    it 'converts nested generic with hash map' do
      expect(to_rbs(parse('Array<Hash{String => Integer}>'))).to eq('Array[Hash[String, Integer]]')
    end

    it 'converts nil to untyped' do
      expect(to_rbs(nil)).to eq('untyped')
    end
  end
end
