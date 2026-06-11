# frozen_string_literal: true

require 'docscribe/plugin'
require_relative '../plugin'

RSpec.describe DocscribePlugins::ApiTagPlugin do
  let(:plugin) { described_class.new }

  before { Docscribe::Plugin::Registry.register(plugin) }
  after  { Docscribe::Plugin::Registry.clear! }

  def rewrite(code, strategy: :safe)
    conf = Docscribe::Config.new({})
    inline(code, strategy: strategy, config: conf)
  end

  describe 'public methods' do
    subject(:out) { rewrite(code) }

    describe 'appends @api public to a public method' do
      let(:code) do
        <<~RUBY
          class Demo
            def greet
              "Hello"
            end
          end
        RUBY
      end

      it { is_expected.to include('# @api public') }
    end

    describe 'appends @api public to a public class method' do
      let(:code) do
        <<~RUBY
          class Demo
            def self.build
              new
            end
          end
        RUBY
      end

      it { is_expected.to include('# @api public') }
    end
  end

  describe 'private methods' do
    subject(:out) { rewrite(code) }

    let(:code) do
      <<~RUBY
        class Demo
          private

          def secret
            42
          end
        end
      RUBY
    end

    it { is_expected.to include('# @api private') }
    it { is_expected.not_to include('# @api public') }
  end

  describe 'protected methods' do
    subject(:out) { rewrite(code) }

    let(:code) do
      <<~RUBY
        class Demo
          protected

          def internal
            true
          end
        end
      RUBY
    end

    it { is_expected.to include('# @api private') }
  end

  describe 'idempotency' do
    let(:code) do
      <<~RUBY
        class Demo
          def foo
            1
          end
        end
      RUBY
    end

    it 'does not duplicate @api tag on second safe run' do
      first  = rewrite(code)
      second = rewrite(first)
      expect(second.scan('# @api public').length).to eq(1)
    end
  end

  describe 'aggressive mode' do
    let(:code) do
      <<~RUBY
        class Demo
          def foo
            1
          end
        end
      RUBY
    end

    it 'appends @api public in aggressive mode' do
      out = rewrite(code, strategy: :aggressive)
      expect(out).to include('# @api public')
    end
  end

  describe 'context' do
    let(:code) do
      <<~RUBY
        class MyService
          def run
            true
          end

          private

          def prepare
            false
          end
        end
      RUBY
    end

    let(:received) { [] }

    let(:spy) do
      target = received
      Class.new(Docscribe::Plugin::Base::TagPlugin) do
        define_method(:call) do |context|
          target << context
          []
        end
      end.new
    end

    before do
      Docscribe::Plugin::Registry.register(spy)
      rewrite(code)
    end

    it { expect(received.map(&:container).uniq).to eq(['MyService']) }
    it { expect(received.map(&:visibility)).to include(:public, :private) }
  end
end
