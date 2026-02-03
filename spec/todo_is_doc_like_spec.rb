# frozen_string_literal: true

RSpec.describe '@todo blocks are doc-like' do
  it 'merges into a block that only contains @todo' do
    code = <<~RUBY
      class A
        # @todo docs
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# @todo docs')
    expect(out).to include('# @param [Object] x')
  end
end
