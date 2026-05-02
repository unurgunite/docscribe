# frozen_string_literal: true

RSpec.describe 'safe strategy params' do
  describe 'adds only missing @param lines' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # Existing docs
          # @param [Object] x correct type
          def foo(x, y); y; end
        end
      RUBY
    end

    it 'adds only missing @param lines and keeps existing @param lines untouched' do
      # Existing doc preserved verbatim
      expect(out).to include(param_tag('x', 'Object', description: 'correct type'))

      # New param added (y)
      expect(out).to include(param_tag('y', 'Object', description: 'Param documentation.'))

      # Should NOT create a second @param for x
      expect(out.scan(/@param \[[^\]]+\] x\b/).size).to eq(1)

      # Safe strategy should not insert the Docscribe header line
      expect(out).not_to include('# +A#foo+')
    end
  end

  describe 'updates @param when type changed' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @param [String] x wrong type
          def foo(x: 1); x; end
        end
      RUBY
    end

    it 'updates existing @param with correct type' do
      expect(out).to include(param_tag('x', 'Integer'))
      expect(out).not_to include(param_tag('x', 'String', description: 'wrong type'))
      expect(out.scan(/@param \[[^\]]+\] x\b/).size).to eq(1)
    end
  end
end
