# frozen_string_literal: true

RSpec.describe Docscribe::Infer do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }

  describe 'begin/rescue/end' do
    describe 'bare begin without rescue' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              begin
                42
              end
            end
          end
        RUBY
      end

      it 'returns Integer' do
        expect(out).to match(header_regex('A', 'foo', 'Integer'))
      end
    end

    describe 'begin/rescue with matching types' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              begin
                :ok
              rescue
                :err
              end
            end
          end
        RUBY
      end

      it 'returns Symbol' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end

    describe 'begin/rescue with different types' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              begin
                :ok
              rescue
                42
              end
            end
          end
        RUBY
      end

      it 'returns Symbol, Integer' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol, Integer'))
      end
    end

    describe 'begin/rescue/else' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              begin
                :ok
              rescue
                :err
              else
                :other
              end
            end
          end
        RUBY
      end

      it 'returns Symbol' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end

    describe 'begin/ensure' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              begin
                :ok
              ensure
                cleanup
              end
            end
          end
        RUBY
      end

      it 'returns Symbol (ensure result ignored)' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end

    describe 'begin/rescue/ensure' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              begin
                :ok
              rescue
                :err
              ensure
                cleanup
              end
            end
          end
        RUBY
      end

      it 'returns Symbol' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end

    describe 'inline rescue modifier' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              risky_call rescue :default
            end
          end
        RUBY
      end

      it 'separates normal (Object) and rescue (Symbol) return tags' do
        expect(out).to match(header_regex('A', 'foo', 'Object')).and include('@return [Symbol]')
      end
    end

    describe 'inline rescue modifier with different types' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              risky_call rescue 42
            end
          end
        RUBY
      end

      it 'separates normal (Object) and rescue (Integer) return tags' do
        expect(out).to match(header_regex('A', 'foo', 'Object')).and include('@return [Integer]')
      end
    end

    describe 'multi-rescue with different types' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              begin
                :ok
              rescue RuntimeError
                :rt
              rescue
                :std
              end
            end
          end
        RUBY
      end

      it 'returns Symbol' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end
  end

  describe 'defined?' do
    describe 'defined? with variable' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              defined?(x)
            end
          end
        RUBY
      end

      it 'returns String?' do
        expect(out).to match(header_regex('A', 'foo', 'String?'))
      end
    end

    describe 'defined? as last expr in method' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              defined?(@ivar)
            end
          end
        RUBY
      end

      it 'returns String?' do
        expect(out).to match(header_regex('A', 'foo', 'String?'))
      end
    end
  end

  describe 'super' do
    describe 'super with no args' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              super
            end
          end
        RUBY
      end

      it 'returns Object' do
        expect(out).to match(header_regex('A', 'foo', 'Object'))
      end
    end

    describe 'super with args' do
      let(:code) do
        <<~RUBY
          class A
            def foo(a)
              super(a)
            end
          end
        RUBY
      end

      it 'returns Object' do
        expect(out).to match(header_regex('A', 'foo', 'Object'))
      end
    end
  end

  describe 'yield' do
    describe 'yield with no args' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              yield
            end
          end
        RUBY
      end

      it 'returns Object' do
        expect(out).to match(header_regex('A', 'foo', 'Object'))
      end
    end

    describe 'yield with args' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              yield(42)
            end
          end
        RUBY
      end

      it 'returns Object' do
        expect(out).to match(header_regex('A', 'foo', 'Object'))
      end
    end
  end

  describe 'case...in (pattern matching)' do
    describe 'case...in with matching types' do
      let(:code) do
        <<~RUBY
          class A
            def foo(x)
              case x
              in Integer then :int
              in String then :str
              end
            end
          end
        RUBY
      end

      it 'returns Symbol' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end

    describe 'case...in with else' do
      let(:code) do
        <<~RUBY
          class A
            def foo(x)
              case x
              in Integer then :int
              in String then :str
              else :other
              end
            end
          end
        RUBY
      end

      it 'returns Symbol' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end

    describe 'case...in with different types' do
      let(:code) do
        <<~RUBY
          class A
            def foo(x)
              case x
              in Integer then 42
              in String then "str"
              end
            end
          end
        RUBY
      end

      it 'returns Integer, String' do
        expect(out).to match(header_regex('A', 'foo', 'Integer, String'))
      end
    end

    describe 'case...in with guard' do
      let(:code) do
        <<~RUBY
          class A
            def foo(x)
              case x
              in Integer if x > 0
                :pos
              in Integer
                :non_pos
              end
            end
          end
        RUBY
      end

      it 'returns Symbol' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end

    describe 'single in pattern (match_pattern)' do
      let(:code) do
        <<~RUBY
          class A
            def foo(x)
              x => Integer
              :matched
            end
          end
        RUBY
      end

      it 'returns Symbol (last expr, not match result)' do
        expect(out).to match(header_regex('A', 'foo', 'Symbol'))
      end
    end
  end
end
