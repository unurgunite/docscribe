# frozen_string_literal: true

require 'parser/source/buffer'
require 'parser/source/tree_rewriter'

RSpec.describe 'merge insert aggregation' do
  it 'applies one insert per end_pos and avoids consecutive blank-comment separators' do
    src = "class A\nend\n"

    buffer = Parser::Source::Buffer.new('(merge-agg)')
    buffer.source = src

    rewriter = Parser::Source::TreeRewriter.new(buffer)

    merge_inserts = Hash.new { |h, k| h[k] = [] }
    end_pos = src.length

    merge_inserts[end_pos] << [
      10,
      "  #\n  " \
      "# @param [Object] x Param documentation.\n"
    ]

    merge_inserts[end_pos] << [
      20,
      "  #\n  " \
      "# @param [Object] y Param documentation.\n"
    ]

    Docscribe::InlineRewriter.send(
      :apply_merge_inserts!,
      rewriter: rewriter,
      buffer: buffer,
      merge_inserts: merge_inserts
    )

    out = rewriter.process

    expect(out).to include('@param [Object] x')
    expect(out).to include('@param [Object] y')

    # No consecutive blank comment separator lines
    expect(out).not_to match(/^\s*#\s*$\n^\s*#\s*$/m)
  end
end
