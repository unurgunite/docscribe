# frozen_string_literal: true

RSpec.describe 'TagPlugin integration' do
  after { Docscribe::Plugin::Registry.clear! }

  let(:since_plugin) do
    Class.new(Docscribe::Plugin::Base::TagPlugin) do
      def call(_context)
        [Docscribe::Plugin::Tag.new(name: 'since', text: '1.3.0')]
      end
    end.new
  end

  let(:code) do
    <<~RUBY
      class Demo
        def foo
          1
        end
      end
    RUBY
  end

  describe 'in aggressive mode' do
    subject(:out) { inline(code, strategy: :aggressive) }

    it 'appends plugin tags' do
      Docscribe::Plugin::Registry.register(since_plugin)
      expect(out).to include('# @since 1.3.0')
    end

    it 'isolates broken plugins and continues' do
      broken = ->(_ctx) { raise 'boom' }
      Docscribe::Plugin::Registry.register(broken)
      Docscribe::Plugin::Registry.register(since_plugin)

      expect do
        out
      end.not_to raise_error
    end

    describe 'when passes correct context to plugin' do
      let(:code) do
        <<~RUBY
          class MyClass
            def greet
              "hi"
            end
          end
        RUBY
      end

      it 'passes correct context to plugin' do
        received = nil
        spy = lambda { |ctx|
          received = ctx
          []
        }
        Docscribe::Plugin::Registry.register(spy)

        inline(code, strategy: :aggressive)
        expect(received).not_to be_nil
        expect(received.container).to eq('MyClass')
        expect(received.method_name).to eq(:greet)
        expect(received.scope).to eq(:instance)
        expect(received.visibility).to eq(:public)
        expect(received.inferred_return).to eq('String')
      end
    end
  end

  describe 'in safe mode' do
    subject(:out) { inline(code) }

    it 'appends plugin tags when method has no doc block' do
      Docscribe::Plugin::Registry.register(since_plugin)
      expect(out).to include('# @since 1.3.0')
    end

    it 'does not duplicate plugin tags on second safe run' do
      Docscribe::Plugin::Registry.register(since_plugin)
      second = inline(out)
      expect(second.scan('# @since 1.3.0').length).to eq(1)
    end
  end
end
