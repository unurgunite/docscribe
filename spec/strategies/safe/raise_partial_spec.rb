# frozen_string_literal: true

RSpec.describe 'safe strategy partial @raise' do
  describe 'keeps existing @raise' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @raise [MyError] already documented
          def foo
            risky
          rescue FooError, BarError
            1
          end
        end
      RUBY
    end

    it 'keeps existing @raise and appends missing inferred @raise types' do
      # Existing preserved
      expect(out).to include('# @raise [MyError] already documented')

      # Missing inferred ones appended
      expect(out).to include('# @raise [FooError]')
      expect(out).to include('# @raise [BarError]')

      # Ensure we didn't duplicate MyError as a generated line
      expect(out.scan(/@raise \[MyError\]/).size).to eq(1)
    end
  end

  describe 'does not append inferred @raise type that is already documented' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @raise [FooError] already documented
          def foo
            risky
          rescue FooError, BarError
            1
          end
        end
      RUBY
    end

    it 'does not append an inferred @raise type that is already documented' do
      # Should not create a second FooError line
      expect(out.scan(/@raise \[FooError\]/).size).to eq(1)

      # But should add BarError
      expect(out).to include('# @raise [BarError]')
    end
  end
end
