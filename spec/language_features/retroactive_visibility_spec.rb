# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }
  let(:code) do
    <<~RUBY
      class A
        def foo; 1; end
        private :foo
      end
    RUBY
  end

  it 'marks method as private when private :name appears after def', :aggregate_failures do
    expect(out).to include('# +A#foo+')
    # Ensure the doc block for foo includes @private
    expect(out).to match(/# \+A#foo\+.*?\n.*?# @private/m)
  end
end
