# frozen_string_literal: true

RSpec.describe '--merge raise' do
  it 'adds @raise when none exists and inference finds raises' do
    code = <<~RUBY
      class A
        # @todo docs
        def foo
          risky
        rescue FooError
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# @todo docs')
    expect(out).to include('# @raise [FooError]')
  end

  it 'does not append inferred @raise types that are already documented' do
    code = <<~RUBY
      class A
        # @todo docs
        # @raise [FooError] already documented
        def foo
          risky
        rescue FooError
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    # Still exactly one @raise line
    expect(out.scan(/^\s*#\s*@raise\b/).size).to eq(1)
    expect(out).to include('# @raise [FooError] already documented')
  end
end
