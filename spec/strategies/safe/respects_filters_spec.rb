# frozen_string_literal: true

RSpec.describe 'safe strategy respects filters' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('filter' => { 'exclude' => ['A#foo'] }) }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs
        def foo(x); x; end
      end
    RUBY
  end

  it 'does not merge into doc blocks for excluded methods' do
    expect(out).to eq(code)
  end
end
