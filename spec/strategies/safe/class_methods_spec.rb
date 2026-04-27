# frozen_string_literal: true

RSpec.describe 'safe strategy class methods' do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs
        def self.foo(x); x; end
      end
    RUBY
  end

  it 'merges missing tags for def self.foo' do
    expect(out).to include(param_tag('x', 'Object'))
    expect(out).to include('# @return [Object]')
    expect(out).not_to include('# +A.foo+') # merge should not insert Docscribe header
  end
end
