# frozen_string_literal: true

RSpec.describe 'safe strategy return' do
  describe 'adds @return when missing' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          def foo; 1; end
        end
      RUBY
    end

    it 'adds @return when missing' do
      expect(out).to include('# @todo docs')
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# +A#foo+')
    end
  end

  describe 'does not add another @return when one already exists' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @return [String] already documented
          def foo; 1; end
        end
      RUBY
    end

    it 'does not add another @return when one already exists' do
      expect(out).to include('# @return [String] already documented')
      expect(out.scan(/^\s*#\s*@return\b/).size).to eq(1)
    end
  end
end
