# frozen_string_literal: true

RSpec.describe 'safe strategy idempotency' do
  subject(:out2) { inline(out1) }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs
        def foo(x); x; end
      end
    RUBY
  end

  let(:out1) { inline(code) }

  it 'is idempotent' do
    expect(out2).to eq(out1)
  end
end
