# frozen_string_literal: true

require 'parser/source/buffer'
require 'parser/source/tree_rewriter'

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) do
    rewriter = Parser::Source::TreeRewriter.new(buffer)
    merge_inserts = Hash.new { |h, k| h[k] = [] }
    end_pos = src.length

    merge_inserts[end_pos] << [
      10,
      "  #\n  " \
      "# @!attribute [r] a\n  " \
      "#   @return [Object]\n"
    ]

    merge_inserts[end_pos] << [
      20,
      "  #\n  " \
      "# @!attribute [r] b\n  " \
      "#   @return [Object]\n"
    ]

    described_class.send(
      :apply_merge_inserts!,
      rewriter: rewriter,
      buffer: buffer,
      merge_inserts: merge_inserts
    )

    rewriter.process
  end

  let(:src) { "class A\nend\n" }
  let(:buffer) { Parser::Source::Buffer.new('(merge-agg-repeat)').tap { |b| b.source = src } }

  it { expect(out.scan(/@!attribute \[r\] a/).size).to eq(1) }
  it { expect(out.scan(/@!attribute \[r\] b/).size).to eq(1) }

  it 'includes duplicate @return lines (once per attribute)' do
    expect(out.scan(/#\s+@return \[Object\]/).size).to eq(2)
  end

  it 'avoids consecutive blank comment separator lines' do
    expect(out).not_to match(/^\s*#\s*$\n^\s*#\s*$/m)
  end
end
