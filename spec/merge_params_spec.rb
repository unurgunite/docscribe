# frozen_string_literal: true

RSpec.describe 'safe strategy params' do
  it 'adds only missing @param lines and keeps existing @param lines untouched' do
    code = <<~RUBY
      class A
        # Existing docs
        # @param [String] x already documented
        def foo(x, y); y; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)

    # Existing doc preserved verbatim
    expect(out).to include(param_tag('x', 'String', description: 'already documented'))

    # New param added (y)
    expect(out).to include(param_tag('y', 'Object', description: 'Param documentation.'))

    # Should NOT create a second @param for x
    expect(out.scan(/@param \[[^\]]+\] x\b/).size).to eq(1)

    # Safe strategy should not insert the Docscribe header line
    expect(out).not_to include('# +A#foo+')
  end
end
