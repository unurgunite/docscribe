# frozen_string_literal: true

RSpec.describe 'aggressive strategy preserves rubocop directives' do
  let(:conf) { Docscribe::Config.new }

  describe 'preserves leading rubocop directives but replaces doc blocks' do
    subject(:out) { inline(code, strategy: :aggressive, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          # rubocop:disable Metrics/AbcSize
          # old doc
          # @return [String]
          def foo
            1
          end
        end
      RUBY
    end

    it { is_expected.to include('# rubocop:disable Metrics/AbcSize') }
    it { is_expected.to include('# +A#foo+ -> Integer') }
    it { is_expected.to include('# @return [Integer]') }
    it { is_expected.not_to include('# old doc') }
    it { is_expected.not_to include('# @return [String]') }
  end
end
