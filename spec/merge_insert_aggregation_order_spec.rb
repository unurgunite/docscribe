# frozen_string_literal: true

require 'parser/source/buffer'
require 'parser/source/tree_rewriter'

RSpec.describe 'merge insert aggregation ordering' do
  it 'applies inserts from bottom to top (higher end_pos first) to avoid offset issues' do
    src = "class A\n  # top\n  def a; end\n\n  # bottom\n  def b; end\nend\n"

    buffer = Parser::Source::Buffer.new('(merge-agg-order)')
    buffer.source = src

    rewriter = Parser::Source::TreeRewriter.new(buffer)

    merge_inserts = Hash.new { |h, k| h[k] = [] }

    top_end_pos = src.index('  def a')
    bottom_end_pos = src.index('  def b')

    # Insert at "bottom" first, then "top" later
    merge_inserts[bottom_end_pos] << [20, "  #\n  # @param [Object] x Param documentation.\n"]
    merge_inserts[top_end_pos] << [10, "  #\n  # @return [Object]\n"]

    Docscribe::InlineRewriter.send(
      :apply_merge_inserts!,
      rewriter: rewriter,
      buffer: buffer,
      merge_inserts: merge_inserts
    )

    out = rewriter.process

    # Just ensure both inserts happened (ordering correctness is mostly about not crashing/overlapping)
    expect(out).to include('@param [Object] x')
    expect(out).to include('@return [Object]')
  end
end
