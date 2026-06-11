# frozen_string_literal: true

RSpec.describe Docscribe::Plugin::Base::TagPlugin do
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

    before { Docscribe::Plugin::Registry.register(since_plugin) }

    it { expect(out).to include('# @since 1.3.0') }

    it 'isolates broken plugins and continues' do
      Docscribe::Plugin::Registry.register(->(_ctx) { raise 'boom' })
      expect { out }.not_to raise_error
    end

    describe 'when passes correct context to plugin' do
      subject(:result) do
        received = nil
        spy = lambda { |ctx|
          received = ctx
          []
        }
        Docscribe::Plugin::Registry.register(spy)
        inline(code, strategy: :aggressive)
        received
      end

      let(:code) do
        <<~RUBY
          class MyClass
            def greet
              "hi"
            end
          end
        RUBY
      end

      it { expect(result).not_to be_nil }
      it { expect(result.container).to eq('MyClass') }
      it { expect(result.method_name).to eq(:greet) }
      it { expect(result.scope).to eq(:instance) }
      it { expect(result.visibility).to eq(:public) }
      it { expect(result.inferred_return).to eq('String') }
    end
  end

  describe 'in safe mode' do
    subject(:out) { inline(code) }

    before { Docscribe::Plugin::Registry.register(since_plugin) }

    it { expect(out).to include('# @since 1.3.0') }

    it 'does not duplicate plugin tags on second safe run' do
      expect(inline(out).scan('# @since 1.3.0').length).to eq(1)
    end
  end
end
