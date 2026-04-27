# frozen_string_literal: true

RSpec.describe 'safe strategy module_function note de-dup' do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      module M
        module_function

        # @todo docs
        # @note module_function: when included, also defines #foo (instance visibility: private)
        def foo(x); x; end
      end
    RUBY
  end

  it 'does not add a second module_function @note if one already exists' do
    expect(out.scan(/@note module_function:/).size).to eq(1)
    expect(out).to include(param_tag('x', 'Object'))
  end
end
