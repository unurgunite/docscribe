# frozen_string_literal: true

RSpec.describe Docscribe::Plugin::Base::CollectorPlugin do
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
          results << define_method_result(node, meth_name)
        end
        results
      end

      private

      def define_method_result(node, meth_name)
        indent = node.loc.expression.source_line[/\A[ \t]*/] || ''
        doc = "#{indent}# Dynamic method: #{meth_name}\n" \
              "#{indent}# @return [Object]\n"
        { anchor_node: node, doc: doc }
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

    before { Docscribe::Plugin::Registry.register(define_method_plugin) }

    it { expect(out).to include('# Dynamic method: hello') }
    it { expect(out).to include('# @return [Object]') }

    it 'is idempotent' do
      second = inline(out)
      expect(second.scan('# Dynamic method: hello').length).to eq(1)
    end
  end

  describe 'in aggressive mode' do
    subject(:out) { inline(code, strategy: :aggressive) }

    before { Docscribe::Plugin::Registry.register(define_method_plugin) }

    let(:broken_plugin) do
      Class.new(Docscribe::Plugin::Base::CollectorPlugin) do
        def collect(_ast, _buffer)
          raise 'boom'
        end
      end.new
    end

    it { expect(out).to include('# Dynamic method: hello') }
    it { expect(out).not_to include('# old doc') }

    it 'isolates broken collector plugins and continues' do
      Docscribe::Plugin::Registry.register(broken_plugin)
      expect { out }.not_to raise_error
    end
  end
end
