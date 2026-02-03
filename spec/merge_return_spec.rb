# frozen_string_literal: true

RSpec.describe '--merge return' do
  it 'adds @return when missing' do
    code = <<~RUBY
      class A
        # @todo docs
        def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# @todo docs')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# +A#foo+')
  end

  it 'does not add another @return when one already exists' do
    code = <<~RUBY
      class A
        # @todo docs
        # @return [String] already documented
        def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# @return [String] already documented')
    expect(out.scan(/^\s*#\s*@return\b/).size).to eq(1)
  end
end
