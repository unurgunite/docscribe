# frozen_string_literal: true

RSpec.describe Docscribe::Infer do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'header' => true }) }

  describe '|| (or) with two literals' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            :a || :b
          end
        end
      RUBY
    end

    it 'returns Symbol' do
      expect(out).to match(header_regex('A', 'foo', 'Symbol'))
    end
  end

  describe '|| (or) with symbol and nil' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            :a || nil
          end
        end
      RUBY
    end

    it 'returns Symbol?' do
      expect(out).to match(header_regex('A', 'foo', 'Symbol?'))
    end
  end

  describe '|| (or) with ternary result and string' do
    let(:code) do
      <<~RUBY
        class A
          def foo(cond)
            (cond ? 42 : nil) || "fallback"
          end
        end
      RUBY
    end

    it 'returns Integer?, String' do
      expect(out).to match(header_regex('A', 'foo', 'Integer?, String'))
    end
  end

  describe '&& (and) with two literals' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            :a && :b
          end
        end
      RUBY
    end

    it 'returns Symbol' do
      expect(out).to match(header_regex('A', 'foo', 'Symbol'))
    end
  end

  describe '&& (and) with nil and symbol' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            nil && :b
          end
        end
      RUBY
    end

    it 'returns Symbol?' do
      expect(out).to match(header_regex('A', 'foo', 'Symbol?'))
    end
  end

  describe '&& (and) with ternary result and string' do
    let(:code) do
      <<~RUBY
        class A
          def foo(cond)
            (cond ? 42 : nil) && "truthy"
          end
        end
      RUBY
    end

    it 'returns Integer?, String' do
      expect(out).to match(header_regex('A', 'foo', 'Integer?, String'))
    end
  end

  describe 'true && x.to_s || "default"' do
    let(:code) do
      <<~RUBY
        class A
          def foo(x)
            true && x.to_s || "default"
          end
        end
      RUBY
    end

    it 'returns Boolean, String' do
      skip_unless_rbs_available!
      expect(out).to match(header_regex('A', 'foo', 'Boolean, String'))
    end
  end

  describe 'chained || with nil, false, 42' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            nil || false || 42
          end
        end
      RUBY
    end

    it 'returns Boolean?, Integer' do
      expect(out).to match(header_regex('A', 'foo', 'Boolean?, Integer'))
    end
  end

  describe 'chained && with 1, "a", :sym' do
    let(:code) do
      <<~RUBY
        class A
          def foo
            1 && "a" && :sym
          end
        end
      RUBY
    end

    it 'returns Integer, String, Symbol' do
      expect(out).to match(header_regex('A', 'foo', 'Integer, String, Symbol'))
    end
  end

  describe 'complex true && a || b && c' do
    let(:code) do
      <<~RUBY
        class A
          def foo(x, y)
            true && x.to_s || y.to_s && "fallback"
          end
        end
      RUBY
    end

    it 'returns Boolean, String' do
      skip_unless_rbs_available!
      expect(out).to match(header_regex('A', 'foo', 'Boolean, String'))
    end
  end
end
