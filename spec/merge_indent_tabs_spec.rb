# frozen_string_literal: true

RSpec.describe '--merge indentation' do
  it 'preserves tab indentation in merged additions' do
    code = "class A\n\t# @todo docs\n\tdef foo(x)\n\t  x\n\tend\nend\n"

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    # The merged @param line should start with a tab
    expect(out).to include("\t# @param [Object] x")
  end
end
