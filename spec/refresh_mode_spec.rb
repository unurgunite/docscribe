# frozen_string_literal: true

RSpec.describe 'aggressive strategy behavior' do
  it 'replaces an existing contiguous comment block above a method' do
    code = <<~RUBY
      class A
        # old doc
        # @return [String]
        def foo
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :aggressive)

    expect(out).to include('# +A#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# old doc')
    expect(out).not_to include('# @return [String]')
  end

  it 'safe strategy inserts docs non-destructively when only a normal comment exists above' do
    code = <<~RUBY
      class A
        # just a normal comment
        def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)

    expect(out).to include('# just a normal comment')
    expect(out).to include('# +A#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
  end
end
