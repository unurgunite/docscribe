# frozen_string_literal: true

RSpec.describe 'safe strategy tag sorting' do
  describe 'contiguous tag run' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # Existing docs
          # @return [Integer]
          def foo(x); x; end
        end
      RUBY
    end

    it 'sorts merged tags inside a contiguous tag run' do
      expect(out).to match(
        /# Existing docs\n\s*#{Regexp.escape(param_tag('x', 'Object'))}\n\s*# @return \[Integer\]/
      )
    end
  end

  describe 'blank comment separator' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @return [Integer]
          #
          def foo(x); x; end
        end
      RUBY
    end

    it 'does not sort across a blank comment separator' do
      expect(out).to match(
        /# @return \[Integer\]\n\s*#\n\s*#{Regexp.escape(param_tag('x', 'Object'))}/
      )
    end
  end

  describe 'existing param text' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @return [Integer]
          # @param [Object] x blah-blah
          def foo(x); x; end
        end
      RUBY
    end

    it 'preserves existing param text when sorting' do
      expect(out).to match(
        /# @param \[Object\] x blah-blah\n\s*# @return \[Integer\]/
      )
      expect(out).not_to include(param_tag('x', 'Object'))
    end
  end
end
