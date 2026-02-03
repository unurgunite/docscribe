# frozen_string_literal: true

RSpec.describe 'extend self handling' do
  it 'documents methods after `extend self` as module methods (M.foo)' do
    code = <<~RUBY
      module M
        extend self

        def foo(x)
          x
        end
      end
    RUBY

    out = inline(code)

    expect(out).to include('# +M.foo+')
    expect(out).to include('# @param [Object] x')
    expect(out).not_to include('# +M#foo+')
    expect(out).not_to include('@note module_function:')
  end

  it 'retroactively promotes earlier defs when `extend self` appears after them' do
    code = <<~RUBY
      module M
        def foo; 1; end
        extend self
      end
    RUBY

    out = inline(code)

    expect(out).to include('# +M.foo+')
    expect(out).not_to include('# +M#foo+')
    expect(out).not_to include('@note module_function:')
  end

  it 'respects visibility (private methods become private module methods too)' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })

    code = <<~RUBY
      module M
        extend self
        private
        def secret; 1; end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

    expect(out).to include('# +M.secret+')
    expect(out).to match(/# \+M\.secret\+.*?\n.*?# @private/m)
  end
end
