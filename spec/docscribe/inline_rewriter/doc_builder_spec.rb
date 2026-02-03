# frozen_string_literal: true

require 'docscribe/inline_rewriter/doc_builder'

RSpec.describe Docscribe::InlineRewriter::DocBuilder do
  it 'infers types for positional optional args (optarg) without crashing' do
    code = <<~RUBY
      class A
        def foo(x = 1); x; end
      end
    RUBY

    out = inline(code)
    expect(out).to include('# @param [Integer] x')
  end
end
