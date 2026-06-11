# frozen_string_literal: true

RSpec.describe Docscribe::InlineRewriter do
  describe 'appends missing @param lines into an existing doc-like block without replacing it' do
    subject(:out) { inline(code, strategy: :safe) }

    let(:code) do
      <<~RUBY
        class A
          # Existing docs
          # @return [String]
          def foo(x); 1; end
        end
      RUBY
    end

    it :aggregate_failures do
      expect(out).to include('# Existing docs')
      expect(out).to include('# @return [String]')          # preserved
      expect(out).to include(param_tag('x', 'Object'))      # added
      expect(out).not_to include('# +A#foo+')               # we did not insert a whole new block
    end
  end

  describe 'inserts a full doc block when no doc-like block exists' do
    subject(:out) { inline(code, strategy: :safe, config: Docscribe::Config.new('emit' => { 'header' => true })) }

    let(:code) do
      <<~RUBY
        class A
          # NOTE: keep this
          def foo; 1; end
        end
      RUBY
    end

    it 'preserves existing comments' do
      expect(out).to include('# NOTE: keep this')
    end

    it 'inserts full header section' do
      expect(out).to match(header_regex('A', 'foo', 'Integer'))
    end
  end
end
