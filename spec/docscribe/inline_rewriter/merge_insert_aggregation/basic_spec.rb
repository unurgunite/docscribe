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
      "# @param [Object] x Generated param description.\n"
    ]

    merge_inserts[end_pos] << [
      20,
      "  #\n  " \
      "# @param [Object] y Generated param description.\n"
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
  let(:buffer) { Parser::Source::Buffer.new('(merge-agg)').tap { |b| b.source = src } }

  it { expect(out).to include('@param [Object] x') }
  it { expect(out).to include('@param [Object] y') }

  it 'avoids consecutive blank comment separator lines' do
    expect(out).not_to match(/^\s*#\s*$\n^\s*#\s*$/m)
  end
end
