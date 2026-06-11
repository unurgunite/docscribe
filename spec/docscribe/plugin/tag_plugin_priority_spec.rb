# frozen_string_literal: true

RSpec.describe Docscribe::Plugin::Base::TagPlugin do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }
  let(:low) do
    Class.new(Docscribe::Plugin::Base::TagPlugin) do
      def call(_context)
        [Docscribe::Plugin::Tag.new(name: 'since', text: 'LOW')]
      end
    end.new
  end
  let(:high) do
    Class.new(Docscribe::Plugin::Base::TagPlugin) do
      def call(_context)
        [Docscribe::Plugin::Tag.new(name: 'since', text: 'HIGH')]
      end
    end.new
  end
  let(:code) do
    <<~RUBY
      class A
        def foo
          1
        end
      end
    RUBY
  end

  after { Docscribe::Plugin::Registry.clear! }

  before do
    Docscribe::Plugin::Registry.register(low, priority: 1)
    Docscribe::Plugin::Registry.register(high, priority: 10)
  end

  it { expect(out).to include('@since HIGH') }
  it { expect(out).to include('@since LOW') }

  it 'orders high priority before low priority', :aggregate_failures do
    high_idx = out.index('@since HIGH')
    low_idx  = out.index('@since LOW')
    expect(high_idx).not_to be_nil
    expect(low_idx).not_to be_nil
    expect(high_idx).to be < low_idx
  end
end
