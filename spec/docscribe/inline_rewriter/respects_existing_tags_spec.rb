# frozen_string_literal: true

RSpec.describe 'Inline rewriter respects existing tags' do
  describe 'existing @param/@option above the method' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class A
      # @param [String] name The name
      def foo(name); "x"; end
      end
    RUBY

    it 'does not insert when user provided @param/@option above the method' do
      expect(out).not_to include('# +A#foo+')
      expect(out).to include('@param [String] name The name') # original stays
    end
  end

  describe 'existing @return' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class A
      # @return [String] pre-documented
      def bar; "x"; end
      end
    RUBY

    it 'does not insert when user provided @return' do
      expect(out).not_to include('# +A#bar+')
      expect(out).to include('@return [String] pre-documented')
    end
  end
end
