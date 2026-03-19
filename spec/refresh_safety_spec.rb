# frozen_string_literal: true

RSpec.describe '--refresh safety' do
  it 'does not delete non-doc comment blocks (no YARD tags / header)' do
    code = <<~RUBY
      class A
        # NOTE: keep this comment
        def foo; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, rewrite: true)

    expect(out).to include('# NOTE: keep this comment')
    expect(out).to include('# +A#foo+ -> Integer')
  end

  it 'preserves leading SimpleCov nocov directives but still replaces doc blocks' do
    code = <<~RUBY
      class A
        # :nocov:
        # old doc
        # @return [String]
        def foo
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, rewrite: true)

    expect(out).to include('# :nocov:')
    expect(out).to include('# +A#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')

    expect(out).not_to include('# old doc')
    expect(out).not_to include('# @return [String]')
  end

  it 'preserves leading RDoc-style directives but still replaces doc blocks' do
    code = <<~RUBY
      class A
        # :stopdoc:
        # old doc
        # @return [String]
        def foo
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, rewrite: true)

    expect(out).to include('# :stopdoc:')
    expect(out).to include('# +A#foo+ -> Integer')

    expect(out).not_to include('# old doc')
    expect(out).not_to include('# @return [String]')
  end
end
