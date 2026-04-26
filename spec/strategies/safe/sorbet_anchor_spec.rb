# frozen_string_literal: true

RSpec.describe 'Sorbet-aware doc anchoring' do
  subject(:out) { inline_with_sorbet(code, strategy: strategy) }

  let(:code) do
    <<~RUBY
      class Demo
        extend T::Sig

        sig { params(verbose: T::Boolean).returns(Integer) }
        def foo(verbose:)
          "a"
        end
      end
    RUBY
  end
  let(:strategy) { :safe }

  describe 'merging into existing doc above sig' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          # Existing docs
          # @return [Integer]
          sig { params(verbose: T::Boolean).returns(Integer) }
          def foo(verbose:)
            "a"
          end
        end
      RUBY
    end

    it 'merges into an existing doc block above sig instead of inserting a second block' do
      expect(out).to include('# Existing docs')
      expect(out).to include('# @return [Integer]')
      expect(out).to include(param_tag('verbose', 'Boolean'))
      expect(out).not_to match(header_regex('Demo', 'foo', 'Integer'))
      expect(out.scan(/# @return \[Integer\]/).length).to eq(1)
    end
  end

  describe 'detecting legacy doc block between sig and def' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { params(verbose: T::Boolean).returns(Integer) }
          # Existing docs
          # @return [Integer]
          def foo(verbose:)
            "a"
          end
        end
      RUBY
    end

    it 'does not duplicate the existing doc block' do
      expect(out).to include('# Existing docs')
      expect(out).to include(param_tag('verbose', 'Boolean'))
      expect(out).to include('# @return [Integer]')
      expect(out).not_to match(header_regex('Demo', 'foo', 'Integer'))
      expect(out.scan(/# @return \[Integer\]/).length).to eq(1)
    end
  end

  describe 'inserting docs for undocumented Sorbet methods' do
    it 'inserts generated docs above sig' do
      expect(out).to match(
        Regexp.new(<<~'RX', Regexp::EXTENDED)
          ^\s*\#\s+\+Demo\#foo\+\s+->\s+Integer.*\n
          (?:^\s*\#.*\n)*?
          ^\s*\#\s+@param\s+\[Boolean\]\s+verbose\s+Param\s+documentation\.\n
          (?:^\s*\#\s*\n)*?
          ^\s*\#\s+@return\s+\[Integer\]\s*\n
          ^\s*sig\s+\{\s*params\(verbose:\s*T::Boolean\)\.returns\(Integer\)\s*\}\s*\n
          ^\s*def\s+foo\(verbose:\)
        RX
      )
    end
  end

  describe 'aggressive mode' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          # Wrong docs
          # @return [String]
          sig { params(verbose: T::Boolean).returns(Integer) }
          def foo(verbose:)
            "a"
          end
        end
      RUBY
    end

    let(:strategy) { :aggressive }

    it 'removes and rebuilds the doc block above sig' do
      expect(out).to match(header_regex('Demo', 'foo', 'Integer'))
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')
      expect(out).to match(
        /# \+Demo#foo\+ -> Integer.*?\n\s*sig \{ params\(verbose: T::Boolean\)\.returns\(Integer\) \}\n\s*def foo\(verbose:\)/m
      )
    end
  end
end
