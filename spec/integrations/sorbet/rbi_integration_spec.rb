# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'Sorbet RBI integration' do
  describe 'RBI signatures' do
    subject(:out) { inline_with_signature_files(code: code, rbi: rbi) }

    let(:rbi) do
      <<~RBI
        # typed: strict
        class Demo
          extend T::Sig

          sig { params(verbose: T::Boolean, count: Integer).returns(Integer) }
          def foo(verbose:, count:)
          end
        end
      RBI
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(verbose:, count:)
            "a"
          end
        end
      RUBY
    end

    it 'uses RBI signatures for params and return types' do
      expect(out).to match(header_regex('Demo', 'foo', 'Integer'))
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')
      expect(out).to include(param_tag('verbose', 'Boolean'))
      expect(out).to include(param_tag('count', 'Integer'))
      expect(out).not_to include(param_tag('verbose', 'Object'))
      expect(out).not_to include(param_tag('count', 'Object'))
    end
  end

  describe 'RBI over RBS priority' do
    subject(:out) { inline_with_signature_files(code: code, rbi: rbi, rbs: rbs) }

    let(:rbi) do
      <<~RBI
        # typed: strict
        class Demo
          extend T::Sig

          sig { returns(Integer) }
          def foo
          end
        end
      RBI
    end

    let(:rbs) do
      <<~RBS
        class Demo
          def foo: () -> Symbol
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo
            "a"
          end
        end
      RUBY
    end

    it 'prefers RBI over RBS when both are present' do
      expect(out).to match(header_regex('Demo', 'foo', 'Integer'))
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [Symbol]')
      expect(out).not_to include('# @return [String]')
    end
  end

  describe 'invalid RBI fallback' do
    subject(:out) { inline_with_signature_files(code: code, rbi: bad_rbi) }

    let(:bad_rbi) do
      <<~RBI
        class Demo
          extend T::Sig

          sig { params(x: Integer).returns( }
          def foo(x)
          end
        end
      RBI
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(x)
            "a"
          end
        end
      RUBY
    end

    it 'falls back cleanly to inference when an RBI file cannot be parsed' do
      expect(out).to match(header_regex('Demo', 'foo', 'String'))
      expect(out).to include('# @return [String]')
      expect(out).to include(param_tag('x', 'Object'))
    end
  end

  describe 'inline sig priority' do
    subject(:out) { inline_with_signature_files(code: code, rbi: rbi, rbs: rbs) }

    let(:rbi) do
      <<~RBI
        # typed: strict
        class Demo
          extend T::Sig

          sig { returns(Integer) }
          def foo
          end
        end
      RBI
    end

    let(:rbs) do
      <<~RBS
        class Demo
          def foo: () -> Symbol
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { returns(Float) }
          def foo
            "a"
          end
        end
      RUBY
    end

    it 'prefers inline Sorbet sigs over RBI, RBS, and inference' do
      expect(out).to match(header_regex('Demo', 'foo', 'Float'))
      expect(out).to include('# @return [Float]')
      expect(out).not_to include('# @return [Integer]')
      expect(out).not_to include('# @return [Symbol]')
      expect(out).not_to include('# @return [String]')
    end
  end
end
