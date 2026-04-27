# frozen_string_literal: true

RSpec.describe 'receiver-based containers' do
  describe 'def Foo.bar' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          def Foo.bar; 1; end
        end
      RUBY
    end

    it 'documents `def Foo.bar` under Foo (not the lexical container)' do
      expect(out).to include('# +Foo.bar+')
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# +A.bar+')
    end
  end

  describe 'class << Foo with private :name' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          class << Foo
            def bar; 1; end
            private :bar
          end
        end
      RUBY
    end

    it 'documents methods inside `class << Foo` under Foo and supports private :name retroactively' do
      expect(out).to include('# +Foo.bar+')
      expect(out).to match(/# \+Foo\.bar\+.*?\n.*?# @private/m)
    end
  end

  describe 'class << Foo does not leak' do
    subject(:out) { inline(code) }

    let(:code) do
      <<~RUBY
        class A
          class << Foo
            def bar; 1; end
          end

          def baz; 2; end
        end
      RUBY
    end

    it 'does not leak the `class << Foo` container into subsequent lexical defs' do
      expect(out).to include('# +Foo.bar+')
      expect(out).to include('# +A#baz+')
    end
  end
end
