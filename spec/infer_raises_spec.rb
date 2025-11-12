# frozen_string_literal: true

RSpec.describe 'Inline rewriter @raise inference' do
  def inline(code)
    StingrayDocsInternal::InlineRewriter.insert_comments(code)
  end

  it 'adds @raise for explicit exception classes rescued' do
    code = <<~RUBY
      class X
      def a
      do_stuff
      rescue Foo, Bar
      # handle
      end
      end
    RUBY
    out = inline(code)
    expect(out).to include('@raise [Foo]')
    expect(out).to include('@raise [Bar]')
  end

  it 'adds @raise [StandardError] when rescue has no classes' do
    code = <<~RUBY
      class X
      def b
      risky
      rescue
      noop
      end
      end
    RUBY
    out = inline(code)
    expect(out).to include('@raise [StandardError]')
  end

  it 'does not add @raise if there is no rescue at all' do
    code = <<~RUBY
      class X
      def c
      :ok
      end
      end
    RUBY
    out = inline(code)
    expect(out).not_to match(/^\s*# @raise \[/)
  end
end
