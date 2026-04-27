# frozen_string_literal: true

RSpec.describe 'safe strategy (attrs)' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true }) }

  context 'when some attrs are already documented' do
    let(:code) do
      <<~RUBY
        class A
          # @!attribute [r] a
          #   @return [Object]
          attr_reader :a, :b
        end
      RUBY
    end

    it 'appends missing @!attribute blocks for undocumented attr names' do
      expect(out).to include('# @!attribute [r] a')
      expect(out).to include('# @!attribute [r] b') # added
    end
  end

  context 'when there is no doc-like block (only a normal comment)' do
    let(:code) do
      <<~RUBY
        class A
          # NOTE: keep this
          attr_reader :name
        end
      RUBY
    end

    it 'inserts full attr docs (even if a normal comment exists)' do
      expect(out).to include('# NOTE: keep this')
      expect(out).to include('# @!attribute [r] name')
    end
  end

  context 'when there is a @todo block' do
    let(:code) do
      <<~RUBY
        class A
          # @todo Document this properly
          attr_reader :name
        end
      RUBY
    end

    it 'treats @todo blocks as doc-like and merges into them' do
      expect(out).to include('# @todo Document this properly')
      expect(out).to include('# @!attribute [r] name')
    end
  end
end
