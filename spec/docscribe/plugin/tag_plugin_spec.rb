# frozen_string_literal: true

require 'docscribe/plugin'

RSpec.describe 'TagPlugin integration' do
  after { Docscribe::Plugin::Registry.clear! }

  let(:since_plugin) do
    Class.new(Docscribe::Plugin::Base::TagPlugin) do
      def call(_context)
        [Docscribe::Plugin::Tag.new(name: 'since', text: '1.3.0')]
      end
    end.new
  end

  it 'appends plugin tags in aggressive mode' do
    Docscribe::Plugin::Registry.register(since_plugin)

    code = <<~RUBY
      class Demo
        def foo
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :aggressive)
    expect(out).to include('# @since 1.3.0')
  end

  it 'appends plugin tags in safe mode when method has no doc block' do
    Docscribe::Plugin::Registry.register(since_plugin)

    code = <<~RUBY
      class Demo
        def foo
          1
        end
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
    expect(out).to include('# @since 1.3.0')
  end

  it 'does not duplicate plugin tags on second safe run' do
    Docscribe::Plugin::Registry.register(since_plugin)

    code = <<~RUBY
      class Demo
        def foo
          1
        end
      end
    RUBY

    first  = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
    second = Docscribe::InlineRewriter.insert_comments(first, strategy: :safe)

    expect(second.scan('# @since 1.3.0').length).to eq(1)
  end

  it 'isolates broken plugins and continues' do
    broken = ->(_ctx) { raise 'boom' }
    Docscribe::Plugin::Registry.register(broken)
    Docscribe::Plugin::Registry.register(since_plugin)

    code = <<~RUBY
      class Demo
        def foo; end
      end
    RUBY

    expect do
      Docscribe::InlineRewriter.insert_comments(code, strategy: :aggressive)
    end.not_to raise_error
  end

  it 'passes correct context to plugin' do
    received = nil
    spy = lambda { |ctx|
      received = ctx
      []
    }
    Docscribe::Plugin::Registry.register(spy)

    code = <<~RUBY
      class MyClass
        def greet(name)
          "hello"
        end
      end
    RUBY

    Docscribe::InlineRewriter.insert_comments(code, strategy: :aggressive)

    expect(received).not_to be_nil
    expect(received.container).to eq('MyClass')
    expect(received.method_name).to eq(:greet)
    expect(received.scope).to eq(:instance)
    expect(received.visibility).to eq(:public)
    expect(received.inferred_return).to eq('String')
  end
end
