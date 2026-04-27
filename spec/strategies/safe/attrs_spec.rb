# frozen_string_literal: true

RSpec.describe 'safe strategy attrs' do
  subject(:out) { inline(code, config: conf) }

  let(:conf) { Docscribe::Config.new('emit' => { 'attributes' => true }) }

  context 'when there is an existing doc-like block' do
    let(:code) do
      <<~RUBY
        class A
          # @todo docs
          # @!attribute [r] a
          #   @return [Object]
          attr_reader :a, :b
        end
      RUBY
    end

    it 'appends missing @!attribute blocks into an existing doc-like block' do
      expect(out).to include('# @todo docs')
      expect(out).to include('# @!attribute [r] a')
      expect(out).to include('# @!attribute [r] b')
      expect(out.scan(/^\s*#\s*@!attribute\b/).size).to eq(2)
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
end
