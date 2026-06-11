# frozen_string_literal: true

require 'docscribe/inline_rewriter/collector'

RSpec.describe Docscribe::InlineRewriter::Collector do
  describe 'visibility handling' do
    subject(:out) { inline(code, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          private def foo; 1; end
        end
      RUBY
    end

    let(:conf) { Docscribe::Config.new('emit' => { 'visibility_tags' => true }) }

    it 'treats `private def foo` as private and emits @private when enabled' do
      expect(out).to include('# @private')
    end
  end

  describe 'Struct.new collection' do
    subject(:ins) do
      buffer = Parser::Source::Buffer.new('(inline)')
      buffer.source = code
      ast = Docscribe::Parsing.parse_buffer(buffer)
      collector = described_class.new(buffer)
      collector.process(ast)
      collector.attr_insertions.find { |i| i.container == 'Foo' }
    end

    let(:code) { "Foo = Struct.new(:a, :b, keyword_init: true)\n" }

    it 'finds the attr insertion' do
      expect(ins).not_to be_nil
    end

    it 'sets access to :rw' do
      expect(ins.access).to eq(:rw)
    end

    it 'collects the attribute names' do
      expect(ins.names).to eq(%i[a b])
    end
  end
end
