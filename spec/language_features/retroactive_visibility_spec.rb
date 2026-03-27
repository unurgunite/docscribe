# frozen_string_literal: true

RSpec.describe 'retroactive visibility' do
  it 'marks method as private when private :name appears after def' do
    code = <<~RUBY
      class A
        def foo; 1; end
        private :foo
      end
    RUBY

    out = inline(code)
    expect(out).to include('# +A#foo+')
    # Ensure the doc block for foo includes @private
    expect(out).to match(/# \+A#foo\+.*?\n.*?# @private/m)
  end
end
