# frozen_string_literal: true

RSpec.describe 'safe strategy idempotency' do
  it 'is idempotent' do
    code = <<~RUBY
      class A
        # @todo docs
        def foo(x); x; end
      end
    RUBY

    out1 = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
    out2 = Docscribe::InlineRewriter.insert_comments(out1, strategy: :safe)

    expect(out2).to eq(out1)
  end
end
