# frozen_string_literal: true

RSpec.describe 'Inline rewriter @raise and conditional @return with rescue' do
  def inline(code)
    StingrayDocsInternal::InlineRewriter.insert_comments(code)
  end

  it 'adds @raise for explicit exception classes and conditional @return for rescue branch' do
    code = <<~RUBY
      class X
        def a
          42
        rescue Foo, Bar
          "fallback"
        end
      end
    RUBY

    out = inline(code)

    # Header shows normal return in happy path
    expect(out).to match(/# \+X#a\+\s*-> Integer/)

    # Rescue exceptions become raise tags
    expect(out).to include('@raise [Foo]')
    expect(out).to include('@raise [Bar]')

    # Normal return
    expect(out).to include('# @return [Integer]')

    # Conditional return in rescue branch
    expect(out).to include('# @return [String] if Foo, Bar')
  end

  it 'adds @raise [StandardError] and conditional @return for bare rescue' do
    code = <<~RUBY
      class X
        def b
          risky
        rescue
          "n"
        end
      end
    RUBY

    out = inline(code)

    # Header shows normal return is unknown (Object) for "risky"
    expect(out).to match(/# \+X#b\+\s*-> Object/)

    # Bare rescue implies StandardError
    expect(out).to include('@raise [StandardError]')

    # Normal return + conditional return for rescue
    expect(out).to include('# @return [Object]')
    expect(out).to include('# @return [String] if StandardError')
  end

  it 'does not add @raise nor conditional return when there is no rescue' do
    code = <<~RUBY
      class X
        def c
          :ok
        end
      end
    RUBY

    out = inline(code)

    expect(out).to match(/# \+X#c\+\s*-> Symbol/)
    expect(out).not_to match(/^\s*# @raise \[/)
    expect(out).not_to match(/^\s*# @return \[.*\]\s+if /)
  end
end
