# frozen_string_literal: true

require 'parser/current'

RSpec.describe Docscribe::Infer::Behavior do
  describe '.analyze' do
    it 'returns default result for nil body' do
      result = described_class.analyze(nil, :foo)
      expect(result[:predicate]).to be(false)
    end

    it 'returns false for has_side_effects with nil body' do
      result = described_class.analyze(nil, :foo)
      expect(result[:has_side_effects]).to be(false)
    end

    it 'returns default result for non-node body' do
      result = described_class.analyze('string', :foo)
      expect(result[:predicate]).to be(false)
    end

    it 'returns false for has_side_effects with non-node body' do
      result = described_class.analyze('string', :foo)
      expect(result[:has_side_effects]).to be(false)
    end

    it 'detects predicate method from method name ending with ?' do
      expect(described_class.analyze(nil, :nil?)[:predicate]).to be(true)
    end

    it 'detects bang method from method name ending with !' do
      expect(described_class.analyze(nil, :save!)[:bang]).to be(true)
    end

    it 'detects ivar assignment as side effect' do
      body = Parser::AST::Node.new(:ivasgn, [:@x, Parser::AST::Node.new(:int, [1])])
      expect(described_class.analyze(body, :foo)[:has_side_effects]).to be(true)
    end

    it 'detects ivar as side effect' do
      body = Parser::AST::Node.new(:ivar, [:@x])
      expect(described_class.analyze(body, :foo)[:has_side_effects]).to be(true)
    end

    it 'detects mutating send as side effect' do
      body = Parser::AST::Node.new(:send, [nil, :<<, Parser::AST::Node.new(:int, [1])])
      expect(described_class.analyze(body, :foo)[:has_side_effects]).to be(true)
    end

    it 'detects push as side effect' do
      body = Parser::AST::Node.new(:send, [nil, :push, Parser::AST::Node.new(:int, [1])])
      expect(described_class.analyze(body, :foo)[:has_side_effects]).to be(true)
    end

    it 'detects delete as side effect' do
      body = Parser::AST::Node.new(:send, [nil, :delete, Parser::AST::Node.new(:sym, [:key])])
      expect(described_class.analyze(body, :foo)[:has_side_effects]).to be(true)
    end

    it 'does not flag non-mutating send as side effect' do
      body = Parser::AST::Node.new(:send, [nil, :length])
      expect(described_class.analyze(body, :foo)[:has_side_effects]).to be(false)
    end
  end

  describe '.default_result' do
    it 'sets predicate for methods ending with ?' do
      expect(described_class.default_result(:empty?)[:predicate]).to be(true)
    end

    it 'does not set bang for predicate methods' do
      expect(described_class.default_result(:empty?)[:bang]).to be(false)
    end

    it 'sets bang for methods ending with !' do
      expect(described_class.default_result(:destroy!)[:bang]).to be(true)
    end

    it 'does not set predicate for bang methods' do
      expect(described_class.default_result(:destroy!)[:predicate]).to be(false)
    end

    it 'returns false predicate for regular method' do
      expect(described_class.default_result(:calculate)[:predicate]).to be(false)
    end

    it 'returns false bang for regular method' do
      expect(described_class.default_result(:calculate)[:bang]).to be(false)
    end

    it 'returns false has_side_effects for regular method' do
      expect(described_class.default_result(:calculate)[:has_side_effects]).to be(false)
    end

    it 'returns false returns_self for regular method' do
      expect(described_class.default_result(:calculate)[:returns_self]).to be(false)
    end

    it 'returns false returns_boolean for regular method' do
      expect(described_class.default_result(:calculate)[:returns_boolean]).to be(false)
    end

    it 'handles nil method name' do
      expect(described_class.default_result(nil)[:predicate]).to be(false)
    end

    it 'handles nil method name for bang' do
      expect(described_class.default_result(nil)[:bang]).to be(false)
    end
  end

  describe '.infer_description' do
    it 'returns nil for methods without side effects or predicate' do
      desc = described_class.infer_description(
        { predicate: false, has_side_effects: false, returns_self: false }, :foo
      )
      expect(desc).to be_nil
    end

    it 'returns predicate description for predicate methods' do
      desc = described_class.infer_description(
        { predicate: true, has_side_effects: false, returns_self: false }, :empty?
      )
      expect(desc).to eq('Returns true if the condition is met, false otherwise')
    end

    it 'returns chaining description for side-effect methods returning self' do
      desc = described_class.infer_description(
        { predicate: false, has_side_effects: true, returns_self: true }, :foo
      )
      expect(desc).to eq('Returns self to allow method chaining')
    end

    it 'returns nil for side-effect methods not returning self' do
      desc = described_class.infer_description(
        { predicate: false, has_side_effects: true, returns_self: false }, :foo
      )
      expect(desc).to be_nil
    end
  end
end
