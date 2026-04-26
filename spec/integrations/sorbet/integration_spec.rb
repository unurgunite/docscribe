# frozen_string_literal: true

RSpec.describe 'Sorbet inline signature integration' do
  describe 'single-line sig' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { params(verbose: T::Boolean, count: Integer).returns(Integer) }
          def foo(verbose:, count:)
            "a"
          end
        end
      RUBY
    end

    subject(:out) { inline_with_sorbet(code) }

    it 'uses inline sigs for params and return types' do
      expect(out).to match(header_regex('Demo', 'foo', 'Integer'))
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')
      expect(out).to include(param_tag('verbose', 'Boolean'))
      expect(out).to include(param_tag('count', 'Integer'))
      expect(out).not_to include(param_tag('verbose', 'Object'))
      expect(out).not_to include(param_tag('count', 'Object'))
    end
  end

  describe 'multiline sig do ... end' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig do
            params(name: T.nilable(String))
              .returns(T.any(String, Integer))
          end
          def foo(name)
            "a"
          end
        end
      RUBY
    end

    subject(:out) { inline_with_sorbet(code) }

    it 'parses multiline signatures' do
      expect(out).to match(
        /# @param \[(?:String\?|String, nil|nil, String)\] name Param documentation\./
      )
      expect(out).to match(
        /# @return \[(?:String, Integer|Integer, String)\]/
      )
      expect(out).not_to include('# @return [String]')
    end
  end

  describe 'class methods' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { returns(Symbol) }
          def self.status
            "ok"
          end
        end
      RUBY
    end

    subject(:out) { inline_with_sorbet(code) }

    it 'uses inline sigs for class methods' do
      expect(out).to match(/# \+Demo\.status\+\s*-> Symbol/)
      expect(out).to include('# @return [Symbol]')
      expect(out).not_to include('# @return [String]')
    end
  end

  describe 'void returns' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { params(flag: T::Boolean).void }
          def foo(flag)
            123
          end
        end
      RUBY
    end

    subject(:out) { inline_with_sorbet(code) }

    it 'renders void returns from inline sigs' do
      expect(out).to match(header_regex('Demo', 'foo', 'void'))
      expect(out).to include('# @return [void]')
      expect(out).to include(param_tag('flag', 'Boolean'))
      expect(out).not_to include('# @return [Integer]')
    end
  end

  describe 'rest arg and kwrest element types' do
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { params(args: Integer, kwargs: Float).returns(Symbol) }
          def foo(*args, **kwargs)
            :ok
          end
        end
      RUBY
    end

    subject(:out) { inline_with_sorbet(code) }

    it 'uses Sorbet rest arg and kwrest element types' do
      expect(out).to include(param_tag('args', 'Array<Integer>'))
      expect(out).to include(param_tag('kwargs', 'Hash<Symbol, Float>'))
      expect(out).to include('# @return [Symbol]')
    end
  end
end
