# frozen_string_literal: true

RSpec.describe '--merge separator behavior' do
  it 'does not add a second blank-comment separator if one already exists' do
    code = <<~RUBY
      class A
        # @todo docs
        #
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    # Must merge @param
    expect(out).to include('# @param [Object] x')

    # Should still have only one consecutive "#" separator line before additions
    expect(out).not_to match(/#\s*\n\s*#\s*\n\s*# @param/)
  end
end
