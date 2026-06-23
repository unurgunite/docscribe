# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Docscribe::Infer do
  before { skip_unless_rbs_available! }

  describe 'implicit self call in rescue branch resolved via RBS container' do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

    let(:rbs) do
      <<~RBS
        class Demo
          def fallback: -> String
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo
            "ok"
          rescue StandardError
            fallback
          end
        end
      RUBY
    end

    it 'resolves return type of main body from implicit self rescue method' do
      expect(out).to include('# @return [String]')
    end

    it 'tags rescue branch with the resolved RBS type' do
      expect(out).to include('# @return [String] if StandardError')
    end
  end

  describe 'implicit self call without rescue resolved via RBS container' do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

    let(:rbs) do
      <<~RBS
        class Demo
          def helper: -> Integer
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo
            helper
          end
        end
      RUBY
    end

    it 'resolves normal return type from implicit self call via RBS' do
      expect(out).to include('# @return [Integer]')
    end
  end

  describe 'implicit self call in multi-rescue resolved via RBS container' do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

    let(:rbs) do
      <<~RBS
        class Demo
          def fallback_a: -> Integer
          def fallback_b: -> String
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo
            "main"
          rescue ArgumentError
            fallback_a
          rescue KeyError
            fallback_b
          end
        end
      RUBY
    end

    it 'resolves main body return type for multi-rescue method' do
      expect(out).to include('# @return [String]')
    end

    it 'resolves first rescue branch type from implicit self call' do
      expect(out).to include('# @return [Integer] if ArgumentError')
    end

    it 'resolves second rescue branch type from implicit self call' do
      expect(out).to include('# @return [String] if KeyError')
    end
  end
end
