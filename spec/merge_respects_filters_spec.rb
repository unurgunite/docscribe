# frozen_string_literal: true

RSpec.describe '--merge respects filters' do
  it 'does not merge into doc blocks for excluded methods' do
    conf = Docscribe::Config.new('filter' => { 'exclude' => ['A#foo'] })

    code = <<~RUBY
      class A
        # @todo docs
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true, config: conf)

    # Should remain unchanged
    expect(out).to eq(code)
  end
end
