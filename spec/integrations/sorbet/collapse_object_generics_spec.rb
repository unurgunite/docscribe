# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  before { skip_unless_sorbet_bridge_available! }

  let(:code) do
    <<~RUBY
      class Demo
        extend T::Sig

        sig { returns(T::Array[T.untyped]) }
        def foo
          []
        end
      end
    RUBY
  end

  let(:strategy) { :safe }

  describe 'when collapse_object_generics is false (default)' do
    subject(:out) do
      inline(code, strategy: strategy,
                   config: Docscribe::Config.new(
                     'sorbet' => { 'enabled' => true, 'collapse_object_generics' => false }
                   ))
    end

    it 'keeps Array<Object> in @return tag' do
      expect(out).to include('# @return [Array<Object>]')
      expect(out).not_to include('# @return [Array]')
    end
  end

  describe 'when collapse_object_generics is true' do
    subject(:out) do
      inline(code, strategy: strategy,
                   config: Docscribe::Config.new(
                     'sorbet' => { 'enabled' => true, 'collapse_object_generics' => true }
                   ))
    end

    it 'collapses Array<Object> to Array in @return tag' do
      expect(out).to include('# @return [Array]')
      expect(out).not_to include('# @return [Array<Object>]')
    end
  end

  describe 'when collapsible generics contain non-Object types' do
    subject(:out) do
      inline(code, strategy: strategy,
                   config: Docscribe::Config.new(
                     'sorbet' => { 'enabled' => true, 'collapse_object_generics' => true }
                   ))
    end

    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { returns(T::Array[Integer]) }
          def foo
            []
          end
        end
      RUBY
    end

    it 'keeps Array<Integer> when collapse_object_generics is true' do
      expect(out).to include('# @return [Array<Integer>]')
      expect(out).not_to include('# @return [Array]')
    end
  end

  describe 'when collapse_generics overrides collapse_object_generics' do
    subject(:out) do
      inline(code, strategy: strategy,
                   config: Docscribe::Config.new(
                     'sorbet' => { 'enabled' => true, 'collapse_generics' => true, 'collapse_object_generics' => false }
                   ))
    end

    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { returns(T::Array[Integer]) }
          def foo
            []
          end
        end
      RUBY
    end

    it 'collapse_generics collapses even non-Object generics' do
      expect(out).to include('# @return [Array]')
      expect(out).not_to include('# @return [Array<Integer>]')
    end
  end
end
