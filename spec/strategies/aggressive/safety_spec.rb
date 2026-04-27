# frozen_string_literal: true

RSpec.describe 'aggressive strategy safety' do
  let(:conf) { Docscribe::Config.new }

  describe 'does not delete non-doc comment blocks (no YARD tags / header)' do
    subject(:out) { inline(code, strategy: :aggressive, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          # NOTE: keep this comment
          def foo; 1; end
        end
      RUBY
    end

    it { is_expected.to include('# NOTE: keep this comment') }
    it { is_expected.to include('# +A#foo+ -> Integer') }
  end

  describe 'preserves leading SimpleCov nocov directives but still replaces doc blocks' do
    subject(:out) { inline(code, strategy: :aggressive, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          # :nocov:
          # old doc
          # @return [String]
          def foo
            1
          end
        end
      RUBY
    end

    it { is_expected.to include('# :nocov:') }
    it { is_expected.to include('# +A#foo+ -> Integer') }
    it { is_expected.to include('# @return [Integer]') }
    it { is_expected.not_to include('# old doc') }
    it { is_expected.not_to include('# @return [String]') }
  end

  describe 'preserves leading RDoc-style directives but still replaces doc blocks' do
    subject(:out) { inline(code, strategy: :aggressive, config: conf) }

    let(:code) do
      <<~RUBY
        class A
          # :stopdoc:
          # old doc
          # @return [String]
          def foo
            1
          end
        end
      RUBY
    end

    it { is_expected.to include('# :stopdoc:') }
    it { is_expected.to include('# +A#foo+ -> Integer') }
    it { is_expected.not_to include('# old doc') }
    it { is_expected.not_to include('# @return [String]') }
  end
end
