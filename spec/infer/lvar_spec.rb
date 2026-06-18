# frozen_string_literal: true

RSpec.describe Docscribe::Infer do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }

  describe 'local variable inference' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = true
            x
          end
        end
      RUBY
    end

    it 'infers Boolean from a boolean literal assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Boolean'))
    end
  end

  describe 'local variable from string literal' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = "hello"
            x
          end
        end
      RUBY
    end

    it 'infers String from a string literal assignment' do
      expect(out).to match(header_regex('A', 'foo', 'String'))
    end
  end

  describe 'local variable from integer literal' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = 42
            x
          end
        end
      RUBY
    end

    it 'infers Integer from an integer literal assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'local variable from symbol literal' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = :ok
            x
          end
        end
      RUBY
    end

    it 'infers Symbol from a symbol literal assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Symbol'))
    end
  end

  describe 'local variable from array literal' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = [1, 2, 3]
            x
          end
        end
      RUBY
    end

    it 'infers Array from an array literal assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Array'))
    end
  end

  describe 'local variable from hash literal' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = { a: 1 }
            x
          end
        end
      RUBY
    end

    it 'infers Hash from a hash literal assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Hash'))
    end
  end

  describe 'multiple local variables' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = true
            y = 42
            y
          end
        end
      RUBY
    end

    it 'resolves the correct variable type when multiple locals exist' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'local variable inside if branch' do
    let(:code) do
      <<~RUBY
        class A
          def foo(cond)
            x = true
            if cond
              x
            else
              42
            end
          end
        end
      RUBY
    end

    it 'resolves local variable type inside if branch' do
      expect(out).to match(header_regex('A', 'foo', 'Boolean'))
    end
  end

  describe 'local variable not used as last expression falls back to inference' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = true
            42
          end
        end
      RUBY
    end

    it 'infers from the last expression directly when lvar is not the last expr' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'instance variable inference' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            @x = 42
            @x
          end
        end
      RUBY
    end

    it 'infers Integer from an instance variable assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'instance variable from string' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            @name = "hello"
            @name
          end
        end
      RUBY
    end

    it 'infers String from an instance variable assignment' do
      expect(out).to match(header_regex('A', 'foo', 'String'))
    end
  end

  describe 'global variable inference' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            $debug = true
            $debug
          end
        end
      RUBY
    end

    it 'infers Boolean from a global variable assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Boolean'))
    end
  end

  describe 'global variable from symbol' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            $mode = :production
            $mode
          end
        end
      RUBY
    end

    it 'infers Symbol from a global variable assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Symbol'))
    end
  end

  describe 'class variable inference' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            @@count = 0
            @@count
          end
        end
      RUBY
    end

    it 'infers Integer from a class variable assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'class variable from array' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            @@items = [1, 2, 3]
            @@items
          end
        end
      RUBY
    end

    it 'infers Array from a class variable assignment' do
      expect(out).to match(header_regex('A', 'foo', 'Array'))
    end
  end

  describe 'local variable assignment as last expression' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            x = 42
          end
        end
      RUBY
    end

    it 'infers Integer when lvasgn is the last expression' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'instance variable assignment as last expression' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            @var = 42
          end
        end
      RUBY
    end

    it 'infers Integer when ivasgn is the last expression' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'instance variable assignment from string as last expression' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            @name = "hello"
          end
        end
      RUBY
    end

    it 'infers String when ivasgn with string is the last expression' do
      expect(out).to match(header_regex('A', 'foo', 'String'))
    end
  end

  describe 'global variable assignment as last expression' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            $debug = true
          end
        end
      RUBY
    end

    it 'infers Boolean when gvasgn is the last expression' do
      expect(out).to match(header_regex('A', 'foo', 'Boolean'))
    end
  end

  describe 'class variable assignment as last expression' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            @@count = 0
          end
        end
      RUBY
    end

    it 'infers Integer when cvasgn is the last expression' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end

  describe 'without RBS' do
    subject(:out) { inline(code, config: conf) }

    let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }

    describe 'instance variable compound assignment (+=) as last expression' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              @var += 123
            end
          end
        RUBY
      end

      it 'infers Integer from @var += 123 via core RBS' do
        skip_unless_rbs_available!
        expect(out).to match(header_regex('A', 'foo', 'Integer'))
      end
    end

    describe 'local variable assigned from method call as last expression' do
      let(:code) do
        <<~RUBY
          class A
            def foo
              x = get_value
            end

            def get_value
              "hello"
            end
          end
        RUBY
      end

      it 'falls back to Object without RBS for method call value' do
        expect(out).to match(header_regex('A', 'foo', 'Object'))
      end
    end
  end

  describe 'with RBS core types' do
    subject(:out) { inline(code, config: config) }

    before { skip_unless_rbs_available! }

    let(:config) do
      Docscribe::Config.new(
        'rbs' => { 'enabled' => true, 'sig_dirs' => [] },
        'emit' => { 'header' => true, 'return_tags' => true }
      )
    end

    describe 'instance variable assigned from method call with known receiver type' do
      let(:code) do
        <<~RUBY
          class Demo
            def foo(arg = 1)
              @result = arg.positive?
            end
          end
        RUBY
      end

      it 'infers Boolean via RBS when assigning method call with known recv type' do
        expect(out).to include('# @return [Boolean]')
      end
    end

    describe 'local variable assignment from method call with known receiver type' do
      let(:code) do
        <<~RUBY
          class Demo
            def foo(arg = '')
              x = arg.to_i
            end
          end
        RUBY
      end

      it 'infers Integer via RBS when lvasgn last expr has known recv type' do
        expect(out).to include('# @return [Integer]')
      end
    end

    describe 'compound assignment: instance variable += literal' do
      let(:code) do
        <<~RUBY
          class Demo
            def foo
              @var += 123
            end
          end
        RUBY
      end

      it 'infers Integer from @var += 123 via RBS argument type fallback' do
        expect(out).to include('# @return [Integer]')
      end
    end

    describe 'compound assignment: local variable += literal' do
      let(:code) do
        <<~RUBY
          class Demo
            def foo
              x += 1
            end
          end
        RUBY
      end

      it 'infers Integer from x += 1 via RBS argument type fallback' do
        expect(out).to include('# @return [Integer]')
      end
    end

    describe 'RHS inference: x = 123 + 1 followed by x' do
      let(:code) do
        <<~RUBY
          class Demo
            def foo
              x = 123 + 1
              x
            end
          end
        RUBY
      end

      it 'propagates Integer from 123 + 1 through local_var_types' do
        expect(out).to include('# @return [Integer]')
      end
    end

    describe 'RHS inference: x = arg.to_s followed by x' do
      let(:code) do
        <<~RUBY
          class Demo
            def foo(arg = 42)
              x = arg.to_s
              x
            end
          end
        RUBY
      end

      it 'propagates String from arg.to_s through local_var_types' do
        expect(out).to include('# @return [String]')
      end
    end
  end
end
