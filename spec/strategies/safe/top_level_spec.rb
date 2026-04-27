# frozen_string_literal: true

RSpec.describe 'top-level methods' do
  subject(:out) { inline(code, strategy: :safe, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }

  context 'when a method is defined outside any class or module' do
    let(:code) { <<~RUBY }
      def foo
        1
      end
    RUBY

    it 'adds documentation' do
      expect(out).to include('Object#foo')
      expect(out).to include('# Method documentation.')
    end
  end

  context 'when a singleton method is defined at top level' do
    let(:code) { <<~RUBY }
      def self.bar
        2
      end
    RUBY

    it 'adds documentation' do
      expect(out).to include('Object.bar')
      expect(out).to include('# Method documentation.')
    end
  end

  context 'when top-level and class methods coexist' do
    let(:code) { <<~RUBY }
      def foo
        1
      end

      class Obj
        def abc(param: {})
          12
        end
      end
    RUBY

    it 'documents both' do
      expect(out).to include('# +Object#foo+')
      expect(out).to include('# +Obj#abc+')
    end
  end
end
