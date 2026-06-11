# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }
  let(:code) do
    <<~RUBY
      class C
        extend self
        def foo; 1; end
      end
    RUBY
  end

  it 'does not treat extend self in a class as module-method mode', :aggregate_failures do
    # In a class body, extend self should not change instance defs into class defs for Docscribe.
    expect(out).to include('# +C#foo+')
    expect(out).not_to include('# +C.foo+')
  end
end
