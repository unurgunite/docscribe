# frozen_string_literal: true

require 'docscribe/plugin'

RSpec.describe 'CollectorPlugin integration' do
  after { Docscribe::Plugin::Registry.clear! }

  let(:define_method_plugin) do
    Class.new(Docscribe::Plugin::Base::CollectorPlugin) do
      def collect(ast, _buffer)
        results = []

        Docscribe::Infer::ASTWalk.walk(ast) do |node|
          next unless node.type == :send

          _recv, meth, name_node, *_rest = *node
          next unless meth == :define_method
          next unless name_node&.type == :sym

          meth_name = name_node.children.first
          indent    = node.loc.expression.source_line[/\A[ \t]*/] || ''

          doc = "#{indent}# Dynamic method: #{meth_name}\n" \
                "#{indent}# @return [Object]\n"

          results << { anchor_node: node, doc: doc }
        end

        results
      end
    end.new
  end

  it 'inserts docs for define_method in safe mode' do
    Docscribe::Plugin::Registry.register(define_method_plugin)

    code = <<~RUBY
      class Demo
        define_method(:hello) { 'hi' }
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)

    expect(out).to include('# Dynamic method: hello')
    expect(out).to include('# @return [Object]')
  end

  it 'is idempotent in safe mode' do
    Docscribe::Plugin::Registry.register(define_method_plugin)

    code = <<~RUBY
      class Demo
        define_method(:hello) { 'hi' }
      end
    RUBY

    first  = Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
    second = Docscribe::InlineRewriter.insert_comments(first, strategy: :safe)

    expect(second.scan('# Dynamic method: hello').length).to eq(1)
  end

  it 'replaces existing doc in aggressive mode' do
    Docscribe::Plugin::Registry.register(define_method_plugin)

    code = <<~RUBY
      class Demo
        # old doc
        define_method(:hello) { 'hi' }
      end
    RUBY

    out = Docscribe::InlineRewriter.insert_comments(code, strategy: :aggressive)

    expect(out).to include('# Dynamic method: hello')
    expect(out).not_to include('# old doc')
  end

  it 'isolates broken collector plugins and continues' do
    broken = Class.new(Docscribe::Plugin::Base::CollectorPlugin) do
      def collect(_ast, _buffer)
        raise 'boom'
      end
    end.new

    Docscribe::Plugin::Registry.register(broken)

    code = <<~RUBY
      class Demo
        def foo; end
      end
    RUBY

    expect do
      Docscribe::InlineRewriter.insert_comments(code, strategy: :safe)
    end.not_to raise_error
  end
end
