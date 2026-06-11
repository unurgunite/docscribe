# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'visibility_tags' => false }) }
  let(:code) do
    <<~RUBY
      class A
        private
        # @todo docs
        def foo(x); x; end
      end
    RUBY
  end

  it 'does not add @private when emit.visibility_tags is false', :aggregate_failures do
    expect(out).to include(param_tag('x', 'Object'))
    expect(out).not_to include('# @private')
  end
end
