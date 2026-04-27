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
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
      expect(out).to include('# @private')
    end
  end

  describe 'Struct.new collection' do
    it 'collects attr insertions for top-level Struct.new constant assignment' do
      buffer = Parser::Source::Buffer.new('(inline)')
      buffer.source = <<~RUBY
        Foo = Struct.new(:a, :b, keyword_init: true)
      RUBY

      ast = Docscribe::Parsing.parse_buffer(buffer)
      collector = described_class.new(buffer)
      collector.process(ast)

      ins = collector.attr_insertions.find { |i| i.container == 'Foo' }

      expect(ins).not_to be_nil
      expect(ins.access).to eq(:rw)
      expect(ins.names).to eq(%i[a b])
    end
  end
end
