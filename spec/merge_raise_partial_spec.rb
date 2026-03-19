# frozen_string_literal: true

RSpec.describe '--merge partial @raise' do
  it 'keeps existing @raise and appends missing inferred @raise types' do
    code = <<~RUBY
      class A
        # @todo docs
        # @raise [MyError] already documented
        def foo
          risky
        rescue FooError, BarError
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    # Existing preserved
    expect(out).to include('# @raise [MyError] already documented')

    # Missing inferred ones appended
    expect(out).to include('# @raise [FooError]')
    expect(out).to include('# @raise [BarError]')

    # Ensure we didn't duplicate MyError as a generated line
    expect(out.scan(/@raise \[MyError\]/).size).to eq(1)
  end

  it 'does not append an inferred @raise type that is already documented' do
    code = <<~RUBY
      class A
        # @todo docs
        # @raise [FooError] already documented
        def foo
          risky
        rescue FooError, BarError
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    # Should not create a second FooError line
    expect(out.scan(/@raise \[FooError\]/).size).to eq(1)

    # But should add BarError
    expect(out).to include('# @raise [BarError]')
  end
end
