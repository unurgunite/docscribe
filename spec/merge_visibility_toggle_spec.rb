# frozen_string_literal: true

RSpec.describe '--merge visibility tags toggle' do
  it 'does not add @private when emit.visibility_tags is false' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => false })

    code = <<~RUBY
      class A
        private
        # @todo docs
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true, config: conf)

    expect(out).to include('# @param [Object] x')
    expect(out).not_to include('# @private')
  end
end
