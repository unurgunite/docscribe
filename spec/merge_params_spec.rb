# frozen_string_literal: true

RSpec.describe '--merge params' do
  it 'adds only missing @param lines and keeps existing @param lines untouched' do
    code = <<~RUBY
      class A
        # Existing docs
        # @param [String] x already documented
        def foo(x, y); y; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    # Existing doc preserved verbatim
    expect(out).to include('# @param [String] x already documented')

    # New param added (y)
    expect(out).to include('# @param [Object] y Param documentation.')

    # Should NOT create a second @param for x
    expect(out.scan(/@param \[[^\]]+\] x\b/).size).to eq(1)

    # Merge mode should not insert the Docscribe header line
    expect(out).not_to include('# +A#foo+')
  end
end
