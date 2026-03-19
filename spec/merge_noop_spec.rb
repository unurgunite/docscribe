# frozen_string_literal: true

RSpec.describe '--merge no-op' do
  it 'does not change output when all relevant tags already exist' do
    code = <<~RUBY
      class A
        # @todo docs
        # @param [Object] x Param documentation.
        # @return [Integer]
        def foo(x); 1; end
      end
    RUBY

    out1 = Docscribe::InlineRewriter.insert_comments(code, merge: true)
    out2 = Docscribe::InlineRewriter.insert_comments(out1, merge: true)

    expect(out1).to eq(code) # first run should do nothing
    expect(out2).to eq(out1) # second run also no-op
  end
end
