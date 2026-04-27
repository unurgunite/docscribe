# frozen_string_literal: true

RSpec.describe 'Inline rewriter inference' do
  describe 'Boolean and Hash from keyword defaults' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class Demo
      def foo(verbose: true, options: {}); 0; end
      end
    RUBY

    it 'infers Boolean and Hash from keyword defaults' do
      expect(out).to include('@param [Boolean] verbose')
      expect(out).to include('@param [Hash] options')
    end
  end

  describe 'Array/Hash/Proc for splats and block' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class Demo
      def foo(*args, **kwargs, &block); 0; end
      end
    RUBY

    it 'infers Array/Hash/Proc for splats and block' do
      expect(out).to include('@param [Array] args')
      expect(out).to include('@param [Hash] kwargs')
      expect(out).to include('@param [Proc] block')
    end
  end

  describe 'Integer and Symbol for return types from literals' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class Demo
      def a; 42; end
      def b; :ok; end
      end
    RUBY

    it 'infers Integer and Symbol for return types from literals' do
      expect(out).to match(header_regex('Demo', 'a', 'Integer'))
      expect(out).to include('@return [Integer]')
      expect(out).to match(header_regex('Demo', 'b', 'Symbol'))
      expect(out).to include('@return [Symbol]')
    end
  end

  describe 'required keyword without default' do
    subject(:out) { inline(code) }

    let(:code) { <<~RUBY }
      class Demo
      def foo(options:, kw:); 0; end
      end
    RUBY

    it 'treats required keyword without default as Object; but options: without default as Hash' do
      expect(out).to include('@param [Hash] options')
      expect(out).to include('@param [Object] kw')
    end
  end
end
