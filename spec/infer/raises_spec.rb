# frozen_string_literal: true

RSpec.describe 'Inline rewriter @raise inference' do
  describe 'rescue with explicit exception classes' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
         class X
           def a
             do_stuff
           rescue Foo, Bar
             # handle
           end
        end
      RUBY
    end

    it 'adds @raise for explicit exception classes rescued' do
      expect(out).to include('@raise [Foo]')
      expect(out).to include('@raise [Bar]')
    end
  end

  describe 'rescue with no exception classes' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class X
          def b
            risky
          rescue
            noop
          end
        end
      RUBY
    end

    it 'adds @raise [StandardError] when rescue has no classes' do
      expect(out).to include('@raise [StandardError]')
    end
  end

  describe 'no rescue' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class X
          def c
            :ok
          end
        end
      RUBY
    end

    it 'does not add @raise if there is no rescue at all' do
      expect(out).not_to match(/^\s*# @raise \[/)
    end
  end

  describe 'explicit raise Foo' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class X
          def a
            raise Foo
          end
        end
      RUBY
    end

    it 'adds @raise [Foo] for explicit raise Foo' do
      expect(out).to include('@raise [Foo]')
    end
  end

  describe 'bare raise' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class X
          def a
            raise
          end
        end
      RUBY
    end

    it 'adds @raise [StandardError] for bare raise' do
      expect(out).to include('@raise [StandardError]')
    end
  end
end
