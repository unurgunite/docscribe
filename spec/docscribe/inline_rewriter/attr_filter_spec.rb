# frozen_string_literal: true

RSpec.describe 'attr_* + filter' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true }, 'filter' => { 'exclude' => ['A#name', 'A#name='] }) }

  let(:code) { <<~RUBY }
    class A
      attr_accessor :name
    end
  RUBY

  it 'does not emit @!attribute when all implied methods are excluded' do
    expect(out).not_to include('@!attribute')
  end
end
