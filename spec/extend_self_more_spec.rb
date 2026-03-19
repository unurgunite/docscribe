# frozen_string_literal: true

RSpec.describe 'extend self extra behaviors' do
  it 'treats `extend self, X` as extend-self mode (documents as M.foo)' do
    code = <<~RUBY
      module M
        extend self, Kernel
        def foo; 1; end
      end
    RUBY

    out = inline(code)
    expect(out).to include('# +M.foo+')
    expect(out).not_to include('# +M#foo+')
    expect(out).not_to include('@note module_function:')
  end

  it 'respects private_class_method after extend self (endpoint becomes private)' do
    conf = Docscribe::Config.new('emit' => { 'visibility_tags' => true })

    code = <<~RUBY
      module M
        extend self
        def foo; 1; end
        private_class_method :foo
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, config: conf)

    expect(out).to include('# +M.foo+')
    expect(out).to match(/# \+M\.foo\+.*?\n.*?# @private/m)
  end

  it 'persists extend self across reopened modules in the same file' do
    code = <<~RUBY
      module M
        extend self
      end

      module M
        def foo; 1; end
      end
    RUBY

    out = inline(code)

    expect(out).to include('# +M.foo+')
    expect(out).not_to include('# +M#foo+')
  end
end
