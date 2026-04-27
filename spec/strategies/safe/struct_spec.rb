# frozen_string_literal: true

RSpec.describe 'safe strategy struct docs' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true }) }

  context 'when Struct.new assignment has a doc-like block' do
    let(:code) do
      <<~RUBY
        # @todo docs
        # @!attribute [rw] a
        # @return [Object]
        # @param value [Object]
        Foo = Struct.new(:a, :b, keyword_init: true)
      RUBY
    end

    it 'appends missing @!attribute blocks into the existing doc-like block' do
      expect(out).to include('# @todo docs')
      expect(out).to include('# @!attribute [rw] a')
      expect(out).to include('# @!attribute [rw] b')
      expect(out.scan(/^\s*#\s*@!attribute\b/).size).to eq(2)
    end
  end

  context 'when there is no doc-like block' do
    let(:code) do
      <<~RUBY
        # NOTE: keep this
        Foo = Struct.new(:name, keyword_init: true)
      RUBY
    end

    it 'inserts full struct docs' do
      expect(out).to include('# NOTE: keep this')
      expect(out).to include('# @!attribute [rw] name')
    end
  end

  context 'when struct is class-based (< Struct.new ...)' do
    let(:code) do
      <<~RUBY
        class Foo < Struct.new(:a, :b, keyword_init: true)
        end
      RUBY
    end

    it 'does not rewrite it into assignment style' do
      expect(out).to include('class Foo < Struct.new(:a, :b, keyword_init: true)')
      expect(out).not_to include('Foo = Struct.new')
    end
  end
end
