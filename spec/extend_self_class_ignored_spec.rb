# frozen_string_literal: true

RSpec.describe 'extend self ignored in classes' do
  it 'does not treat extend self in a class as module-method mode' do
    code = <<~RUBY
      class C
        extend self
        def foo; 1; end
      end
    RUBY

    out = inline(code)

    # In a class body, extend self should not change instance defs into class defs for Docscribe.
    expect(out).to include('# +C#foo+')
    expect(out).not_to include('# +C.foo+')
  end
end
