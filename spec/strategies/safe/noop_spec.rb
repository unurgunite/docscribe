# frozen_string_literal: true

RSpec.describe 'safe strategy no-op' do
  subject(:out2) { inline(out1) }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs
        # @param [Object] x Param documentation.
        # @return [Integer]
        def foo(x); 1; end
      end
    RUBY
  end

  let(:out1) { inline(code) }

  it 'does not change output when all relevant tags already exist' do
    expect(out1).to eq(code) # first run should do nothing
    expect(out2).to eq(out1) # second run also no-op
  end
end
