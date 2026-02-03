# frozen_string_literal: true

RSpec.describe '--refresh / rewrite mode' do
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

    out = Docscribe::InlineRewriter.insert_comments(code, rewrite: true)

    expect(out).to include('# +A#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# old doc')
    expect(out).not_to include('# @return [String]')
  end

  it 'does NOT change anything when rewrite is false and any comment exists immediately above' do
    code = <<~RUBY
      class A
        # just a normal comment
        def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, rewrite: false)
    expect(out).to eq(code)
  end
end
