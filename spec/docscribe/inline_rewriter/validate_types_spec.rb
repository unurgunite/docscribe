# frozen_string_literal: true

require 'docscribe/inline_rewriter'
require 'docscribe/config'

RSpec.describe Docscribe::InlineRewriter do
  subject(:result) do
    described_class.rewrite_with_report(code, strategy: :safe, config: config, file: 'test.rb')
  end

  let(:config) { Docscribe::Config.new('validate_types' => validate) }
  let(:validate) { false }

  describe 'return mismatch' do
    context 'without validate_types' do
      let(:validate) { false }
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end

      it 'does not report mismatch' do
        expect(result[:changes].any? { |c| c[:type] == :updated_return }).to be false
      end
    end

    context 'with validate_types' do
      let(:validate) { true }
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end

      it 'reports updated_return', :aggregate_failures do
        updated = result[:changes].select { |c| c[:type] == :updated_return }
        expect(updated.size).to eq(1)
        expect(updated.first[:message]).to include('Integer').and include('String')
      end
    end

    context 'when inferred is Object fallback' do
      let(:validate) { true }
      let(:code) do
        <<~RUBY
          class Foo
            # @return [String]
            def bar
              unknown_method
            end
          end
        RUBY
      end

      it 'silences mismatch' do
        expect(result[:changes].any? { |c| c[:type] == :updated_return }).to be false
      end
    end
  end

  describe 'invalid syntax' do
    let(:code) do
      <<~RUBY
        class Foo
          # @return [Sym bol]
          def bar
            :x
          end
        end
      RUBY
    end

    it 'reports invalid_type even without validate_types' do
      expect(result[:changes].select { |c| c[:type] == :invalid_type }.size).to eq(1)
    end
  end

  describe 'param mismatch' do
    let(:validate) { true }
    let(:code) do
      <<~RUBY
        class Foo
          # @param [String] x
          # @return [Object]
          def bar(x: 123)
            x
          end
        end
      RUBY
    end

    it 'reports updated_param', :aggregate_failures do
      updated = result[:changes].select { |c| c[:type] == :updated_param }
      expect(updated.size).to eq(1)
      expect(updated.first[:message]).to include('x')
    end
  end
end
