# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs
        def foo(x); x; end
      end
    RUBY
  end

  it 'merges into a block that only contains @todo', :aggregate_failures do
    expect(out).to include('# @todo docs')
    expect(out).to include(param_tag('x', 'Object'))
  end
end
