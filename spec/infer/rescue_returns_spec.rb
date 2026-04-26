# frozen_string_literal: true

RSpec.describe 'Inline rewriter @raise and conditional @return with rescue' do
  describe 'rescue with explicit exception classes' do
    let(:code) do
      <<~RUBY
        class X
          def a
            42
          rescue Foo, Bar
            "fallback"
          end
        end
      RUBY
    end

    subject(:out) { inline(code) }

    it 'adds @raise tags and conditional @return for the rescue branch' do
      expect(out).to match(header_regex('X', 'a', 'Integer'))
      expect(out).to include('@raise [Foo]')
      expect(out).to include('@raise [Bar]')
      expect(out).to include('# @return [Integer]')
      expect(out).to include('# @return [String] if Foo, Bar')
    end
  end

  describe 'bare rescue' do
    let(:code) do
      <<~RUBY
        class X
          def b
            risky
          rescue
            "n"
          end
        end
      RUBY
    end

    subject(:out) { inline(code) }

    it 'adds @raise [StandardError] and conditional @return' do
      expect(out).to match(header_regex('X', 'b', 'Object'))
      expect(out).to include('@raise [StandardError]')
      expect(out).to include('# @return [Object]')
      expect(out).to include('# @return [String] if StandardError')
    end
  end

  describe 'no rescue' do
    let(:code) do
      <<~RUBY
        class X
          def c
            :ok
          end
        end
      RUBY
    end

    subject(:out) { inline(code) }

    it 'does not add @raise nor conditional return' do
      expect(out).to match(header_regex('X', 'c', 'Symbol'))
      expect(out).not_to match(/^\s*# @raise \[/)
      expect(out).not_to match(/^\s*# @return \[.*\]\s+if /)
    end
  end
end
