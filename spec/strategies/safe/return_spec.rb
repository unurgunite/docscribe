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

  describe 'does not add another @return when type matches' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @return [Integer] already correct
          def foo; 1; end
        end
      RUBY
    end

    it 'preserves existing @return when type matches' do
      expect(out).to include('# @return [Integer] already correct')
      expect(out.scan(/^\s*#\s*@return\b/).size).to eq(1)
    end
  end

  describe 'updates @return when type changed' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @return [String] wrong type
          def foo; 1; end
        end
      RUBY
    end

    it 'updates existing @return with correct type' do
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')
      expect(out.scan(/^\s*#\s*@return\b/).size).to eq(1)
    end
  end
end
