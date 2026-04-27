# frozen_string_literal: true

RSpec.describe 'safe strategy raise' do
  describe 'adds @raise when none exists' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          def foo
            risky
          rescue FooError
            1
          end
        end
      RUBY
    end

    it 'adds @raise when none exists and inference finds raises' do
      expect(out).to include('# @todo docs')
      expect(out).to include('# @raise [FooError]')
    end
  end

  describe 'does not append inferred @raise types that are already documented' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @raise [FooError] already documented
          def foo
            risky
          rescue FooError
            1
          end
        end
      RUBY
    end

    it 'does not append inferred @raise types that are already documented' do
      # Still exactly one @raise line
      expect(out.scan(/^\s*#\s*@raise\b/).size).to eq(1)
      expect(out).to include('# @raise [FooError] already documented')
    end
  end
end
