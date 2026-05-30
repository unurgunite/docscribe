# frozen_string_literal: true

RSpec.describe 'TagPlugin priority' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }
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

  it 'runs higher priority TagPlugins first (higher priority tags appear earlier)' do
    low =
      Class.new(Docscribe::Plugin::Base::TagPlugin) do
        def call(_context)
          [Docscribe::Plugin::Tag.new(name: 'since', text: 'LOW')]
        end
      end.new

    high =
      Class.new(Docscribe::Plugin::Base::TagPlugin) do
        def call(_context)
          [Docscribe::Plugin::Tag.new(name: 'since', text: 'HIGH')]
        end
      end.new

    Docscribe::Plugin::Registry.register(low, priority: 1)
    Docscribe::Plugin::Registry.register(high, priority: 10)

    expect(out).to include('@since HIGH')
    expect(out).to include('@since LOW')

    high_idx = out.index('@since HIGH')
    low_idx  = out.index('@since LOW')

    expect(high_idx).not_to be_nil
    expect(low_idx).not_to be_nil
    expect(high_idx).to be < low_idx
  end
end
