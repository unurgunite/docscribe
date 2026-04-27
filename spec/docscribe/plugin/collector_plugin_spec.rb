# frozen_string_literal: true

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

  let(:code) do
    <<~RUBY
      class Demo
        define_method(:hello) { 'hi' }
      end
    RUBY
  end

  describe 'in safe mode' do
    subject(:out) { inline(code) }

    it 'inserts docs for define_method' do
      Docscribe::Plugin::Registry.register(define_method_plugin)
      expect(out).to include('# Dynamic method: hello')
      expect(out).to include('# @return [Object]')
    end

    it 'is idempotent' do
      Docscribe::Plugin::Registry.register(define_method_plugin)
      second = inline(out)
      expect(second.scan('# Dynamic method: hello').length).to eq(1)
    end
  end

  describe 'in aggressive mode' do
    subject(:out) { inline(code, strategy: :aggressive) }

    it 'replaces existing doc' do
      Docscribe::Plugin::Registry.register(define_method_plugin)
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

      expect do
        out
      end.not_to raise_error
    end
  end
end
