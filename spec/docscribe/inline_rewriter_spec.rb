# frozen_string_literal: true

require 'docscribe/inline_rewriter'

RSpec.describe Docscribe::InlineRewriter do
  it 'preserves tab indentation when inserting docs' do
    code = "class A\n\tdef foo; 1; end\nend\n"
    out = inline(code)
    expect(out).to include("\t# +A#foo+ -> Integer")
  end

  it 'uses line indentation for inline modifier defs (private def ...)' do
    code = <<~RUBY
      class A
        private def foo; 1; end
      end
    RUBY

    out = inline(code)
    expect(out).to include('  # +A#foo+ -> Integer')
  end
end
