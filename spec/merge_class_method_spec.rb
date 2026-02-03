# frozen_string_literal: true

RSpec.describe '--merge class methods' do
  it 'merges missing tags for def self.foo' do
    code = <<~RUBY
      class A
        # @todo docs
        def self.foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out).to include('# @param [Object] x')
    expect(out).to include('# @return [Object]')
    expect(out).not_to include('# +A.foo+') # merge should not insert Docscribe header
  end
end
