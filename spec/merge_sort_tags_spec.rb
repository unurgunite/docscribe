# frozen_string_literal: true

RSpec.describe 'safe strategy tag sorting' do
  it 'sorts merged tags inside a contiguous tag run' do
    code = <<~RUBY
      class A
        # Existing docs
        # @return [Integer]
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)

    expect(out).to match(
      /# Existing docs\n\s*#{Regexp.escape(param_tag('x', 'Object'))}\n\s*# @return \[Integer\]/
    )
  end

  it 'does not sort across a blank comment separator' do
    code = <<~RUBY
      class A
        # @return [Integer]
        #
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)

    expect(out).to match(
      /# @return \[Integer\]\n\s*#\n\s*#{Regexp.escape(param_tag('x', 'Object'))}/
    )
  end

  it 'preserves existing param text when sorting' do
    code = <<~RUBY
      class A
        # @return [Integer]
        # @param [Object] x blah-blah
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)

    expect(out).to match(
      /# @param \[Object\] x blah-blah\n\s*# @return \[Integer\]/
    )
    expect(out).not_to include(param_tag('x', 'Object'))
  end
end
