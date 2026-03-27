# frozen_string_literal: true

require 'docscribe/inline_rewriter/collector'

RSpec.describe Docscribe::InlineRewriter::Collector do
  it 'treats `private def foo` as private' do
    code = <<~RUBY
      class A
        private def foo; 1; end
      end
    RUBY

    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })
    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

    expect(out).to match(/# \+A#foo\+.*?\n.*?# @private/m)
  end

  it 'treats `private def foo` as private (emits @private when enabled)' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })

    code = <<~RUBY
      class A
        private def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)
    expect(out).to match(/# \+A#foo\+.*?\n.*?# @private/m)
  end

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
