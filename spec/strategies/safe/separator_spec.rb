# frozen_string_literal: true

RSpec.describe 'safe strategy separator behavior' do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs
        #
        def foo(x); x; end
      end
    RUBY
  end

  it 'does not add a second blank-comment separator if one already exists' do
    # Must merge @param
    expect(out).to include(param_tag('x', 'Object'))

    # Should still have only one consecutive "#" separator line before additions
    expect(out).not_to match(/#\s*\n\s*#\s*\n\s*# @param/)
  end
end
