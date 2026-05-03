# frozen_string_literal: true

RSpec.describe 'safe strategy params' do
  describe 'adds only missing @param lines' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # Existing docs
          # @param [String] x already documented
          def foo(x, y); y; end
        end
      RUBY
    end

    it 'adds only missing @param lines and keeps existing @param lines untouched' do
      expect(out).to include(param_tag('x', 'String', description: 'already documented'))
      expect(out).to include(param_tag('y', 'Object', description: 'Param documentation.'))
      expect(out.scan(/@param \[[^\]]+\] x\b/).size).to eq(1)
      expect(out).not_to include('# +A#foo+')
    end
  end
end
