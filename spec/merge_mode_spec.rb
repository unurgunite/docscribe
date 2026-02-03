# frozen_string_literal: true

RSpec.describe '--merge mode' do
  it 'appends missing @param lines into an existing doc-like block without replacing it' do
    code = <<~RUBY
      class A
        # Existing docs
        # @return [String]
        def foo(x); 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# Existing docs')
    expect(out).to include('# @return [String]')          # preserved
    expect(out).to include('# @param [Object] x')         # added
    expect(out).not_to include('# +A#foo+')               # we did not insert a whole new block
  end

  it 'inserts a full doc block if there is no doc-like block (even if a normal comment exists)' do
    code = <<~RUBY
      class A
        # NOTE: keep this
        def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# NOTE: keep this')
    expect(out).to include('# +A#foo+ -> Integer')
  end
end
