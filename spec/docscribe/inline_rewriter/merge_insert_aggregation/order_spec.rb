# frozen_string_literal: true

require 'parser/source/buffer'
require 'parser/source/tree_rewriter'

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) do
    rewriter = Parser::Source::TreeRewriter.new(buffer)
    merge_inserts = Hash.new { |h, k| h[k] = [] }

    top_end_pos = src.index('  def a')
    bottom_end_pos = src.index('  def b')

    merge_inserts[bottom_end_pos] << [20, "  #\n  # @param [Object] x Generated param description.\n"]
    merge_inserts[top_end_pos] << [10, "  #\n  # @return [Object]\n"]

    described_class.send(
      :apply_merge_inserts!,
      rewriter: rewriter,
      buffer: buffer,
      merge_inserts: merge_inserts
    )

    rewriter.process
  end

  let(:src) { "class A\n  # top\n  def a; end\n\n  # bottom\n  def b; end\nend\n" }
  let(:buffer) { Parser::Source::Buffer.new('(merge-agg-order)').tap { |b| b.source = src } }

  it { expect(out).to include('@param [Object] x') }
  it { expect(out).to include('@return [Object]') }
end
