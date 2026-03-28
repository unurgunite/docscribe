# frozen_string_literal: true

require 'parser/source/buffer'
require 'parser/source/tree_rewriter'

RSpec.describe 'merge insert aggregation (repeated lines)' do
  it 'does not delete repeated lines that are meaningful (e.g. attr @return lines)' do
    src = "class A\nend\n"

    buffer = Parser::Source::Buffer.new('(merge-agg-repeat)')
    buffer.source = src

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

    Docscribe::InlineRewriter.send(
      :apply_merge_inserts!,
      rewriter: rewriter,
      buffer: buffer,
      merge_inserts: merge_inserts
    )

    out = rewriter.process

    expect(out.scan(/@!attribute \[r\] a/).size).to eq(1)
    expect(out.scan(/@!attribute \[r\] b/).size).to eq(1)

    # The repeated @return line must appear twice (once per attribute block)
    expect(out.scan(/#\s+@return \[Object\]/).size).to eq(2)

    # Still: no consecutive separator lines
    expect(out).not_to match(/^\s*#\s*$\n^\s*#\s*$/m)
  end
end
