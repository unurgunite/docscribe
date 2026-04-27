# frozen_string_literal: true

RSpec.describe 'aggressive strategy behavior' do
  describe 'aggressive strategy' do
    let(:conf) { Docscribe::Config.new }

    describe 'replaces an existing contiguous comment block above a method' do
      subject(:out) { inline(code, strategy: :aggressive, config: conf) }

      let(:code) do
        <<~RUBY
          class A
            # old doc
            # @return [String]
            def foo
              1
            end
          end
        RUBY
      end

      it { is_expected.to include('# +A#foo+ -> Integer') }
      it { is_expected.to include('# @return [Integer]') }
      it { is_expected.not_to include('# old doc') }
      it { is_expected.not_to include('# @return [String]') }
    end
  end

  describe 'safe strategy' do
    let(:conf) { Docscribe::Config.new }

    describe 'inserts docs non-destructively when only a normal comment exists above' do
      subject(:out) { inline(code, strategy: :safe, config: conf) }

      let(:code) do
        <<~RUBY
          class A
            # just a normal comment
            def foo; 1; end
          end
        RUBY
      end

      it { is_expected.to include('# just a normal comment') }
      it { is_expected.to include('# +A#foo+ -> Integer') }
      it { is_expected.to include('# @return [Integer]') }
    end
  end
end
