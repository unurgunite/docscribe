# frozen_string_literal: true

RSpec.describe '--merge idempotency' do
  it 'is idempotent' do
    code = <<~RUBY
      class A
        # @todo docs
        def foo(x); x; end
      end
    RUBY

    out1 = Docscribe::InlineRewriter.insert_comments(code, merge: true)
    out2 = Docscribe::InlineRewriter.insert_comments(out1, merge: true)

    expect(out2).to eq(out1)
  end
end
