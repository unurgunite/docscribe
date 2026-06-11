# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      class A
        # rubocop:disable Metrics/AbcSize
        # @todo docs
        def foo(x); x; end
      end
    RUBY
  end

  it 'keeps rubocop:disable lines and merges tags into the same doc block', :aggregate_failures do
    expect(out).to include('# rubocop:disable Metrics/AbcSize')
    expect(out).to include('# @todo docs')
    expect(out).to include(param_tag('x', 'Object'))
  end
end
