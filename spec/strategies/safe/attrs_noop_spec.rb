# frozen_string_literal: true

RSpec.describe 'safe strategy attrs no-op' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true }) }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs
        # @!attribute [r] a
        #   @return [Object]
        # @!attribute [r] b
        #   @return [Object]
        attr_reader :a, :b
      end
    RUBY
  end

  it 'does nothing when all @!attribute blocks already exist' do
    expect(out).to eq(code)
  end
end
