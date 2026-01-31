# frozen_string_literal: true

RSpec.describe 'module_function handling' do
  def inline(code)
    conf = Docscribe::Config.new({})
    Docscribe::InlineRewriter.insert_comments(code, config: conf)
  end

  it 'documents methods after `module_function` (no args) as module methods' do
    code = <<~RUBY
      module M
        module_function
        def foo; 1; end
      end
    RUBY

    out = inline(code)

    expect(out).to include('# +M.foo+')
    expect(out).to include('# @return [Integer]')
  end

  it 'retroactively documents `module_function :foo` as a module method' do
    code = <<~RUBY
      module M
        def foo; 1; end
        def bar; 2; end
        module_function :foo
      end
    RUBY

    out = inline(code)

    expect(out).to include('# +M.foo+')
    expect(out).to include('# +M#bar+')
  end

  it 'handles multiple names in `module_function :foo, :bar`' do
    code = <<~RUBY
      module M
        def foo; 1; end
        def bar; 2; end
        module_function :foo, :bar
      end
    RUBY

    out = inline(code)

    expect(out).to include('# +M.foo+')
    expect(out).to include('# +M.bar+')
  end
end
