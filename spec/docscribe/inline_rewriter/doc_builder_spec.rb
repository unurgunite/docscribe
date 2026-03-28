# frozen_string_literal: true

require 'docscribe/inline_rewriter/doc_builder'

RSpec.describe Docscribe::InlineRewriter::DocBuilder do
  it 'infers types for positional optional args (optarg) without crashing' do
    code = <<~RUBY
      class A
        def foo(x = 1); x; end
      end
    RUBY

    out = inline(code)
    expect(out).to include(param_tag('x', 'Integer'))
  end

  it 'omits the default method message when doc.include_default_message is false' do
    conf = Docscribe::Config.new(
      'emit' => { 'include_default_message' => false }
    )

    code = <<~RUBY
      class Demo
        def bump(foo)
          :ok
        end
      end
    RUBY

    out = inline(code, config: conf)

    expect(out).not_to include('Method documentation.')
    expect(out).to include('# @param [Object] foo Param documentation.')
  end

  it 'omits param placeholder text when doc.include_param_documentation is false' do
    conf = Docscribe::Config.new(
      'emit' => { 'include_param_documentation' => false }
    )

    code = <<~RUBY
      class Demo
        def bump(foo)
          :ok
        end
      end
    RUBY

    out = inline(code, config: conf)

    expect(out).to include('# @param [Object] foo')
    expect(out).not_to include('Param documentation.')
  end

  it 'omits both method and param placeholder text when both flags are false' do
    conf = Docscribe::Config.new(
      'emit' => {
        'include_default_message' => false,
        'include_param_documentation' => false
      }
    )

    code = <<~RUBY
      class Demo
        def bump(foo)
          :ok
        end
      end
    RUBY

    out = inline(code, config: conf)

    expect(out).not_to include('Method documentation.')
    expect(out).not_to include('Param documentation.')
    expect(out).to include('# @param [Object] foo')
  end
end
