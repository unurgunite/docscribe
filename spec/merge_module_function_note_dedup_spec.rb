# frozen_string_literal: true

RSpec.describe '--merge module_function note de-dup' do
  it 'does not add a second module_function @note if one already exists' do
    code = <<~RUBY
      module M
        module_function

        # @todo docs
        # @note module_function: when included, also defines #foo (instance visibility: private)
        def foo(x); x; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, merge: true)

    expect(out.scan(/@note module_function:/).size).to eq(1)
    expect(out).to include('# @param [Object] x')
  end
end
