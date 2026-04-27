# frozen_string_literal: true

RSpec.describe 'Inline rewriter filter' do
  subject(:out) { inline(code, config: config) }

  let(:filter_overrides) { { 'exclude' => ['*#initialize'] } }
  let(:config) { Docscribe::Config.new('filter' => filter_overrides) }

  let(:code) { <<~RUBY }
    class A
      def initialize; end
      def foo; 1; end
    end
  RUBY

  it 'excludes initialize by glob pattern' do
    expect(out).not_to include('+A#initialize+')
    expect(out).to include('+A#foo+')
  end

  describe 'include filter' do
    subject(:out) { inline(code, config: config) }

    let(:filter_overrides) { { 'include' => ['A#foo'] } }
    let(:config) { Docscribe::Config.new('filter' => filter_overrides) }

    let(:code) { <<~RUBY }
      class A
        def foo; 1; end
        def bar; 2; end
      end
    RUBY

    it 'includes only matching methods when include is non-empty' do
      expect(out).to include('+A#foo+')
      expect(out).not_to include('+A#bar+')
    end
  end
end
