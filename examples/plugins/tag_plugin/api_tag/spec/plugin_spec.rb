# frozen_string_literal: true

require 'docscribe/plugin'
require_relative '../plugin'

RSpec.describe DocscribePlugins::ApiTagPlugin do
  let(:plugin) { described_class.new }

  before { Docscribe::Plugin::Registry.register(plugin) }
  after  { Docscribe::Plugin::Registry.clear! }

  # Method documentation.
  #
  # @param [Object] code Param documentation.
  # @param [Symbol] strategy Param documentation.
  # @return [Object]
  def rewrite(code, strategy: :safe)
    conf = Docscribe::Config.new({})
    inline(code, strategy: strategy, config: conf)
  end

  describe 'public methods' do
    it 'appends @api public to a public method' do
      code = <<~RUBY
        class Demo
          def greet
            "Hello"
          end
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @api public')
    end

    it 'appends @api public to a public class method' do
      code = <<~RUBY
        class Demo
          def self.build
            new
          end
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @api public')
    end
  end

  describe 'private methods' do
    it 'appends @api private to a private method' do
      code = <<~RUBY
        class Demo
          private

          def secret
            42
          end
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @api private')
      expect(out).not_to include('# @api public')
    end
  end

  describe 'protected methods' do
    it 'appends @api private to a protected method' do
      code = <<~RUBY
        class Demo
          protected

          def internal
            true
          end
        end
      RUBY

      out = rewrite(code)

      expect(out).to include('# @api private')
    end
  end

  describe 'idempotency' do
    it 'does not duplicate @api tag on second safe run' do
      code = <<~RUBY
        class Demo
          def foo
            1
          end
        end
      RUBY

      first  = rewrite(code)
      second = rewrite(first)

      expect(second.scan('# @api public').length).to eq(1)
    end
  end

  describe 'aggressive mode' do
    it 'appends @api public in aggressive mode' do
      code = <<~RUBY
        class Demo
          def foo
            1
          end
        end
      RUBY

      out = rewrite(code, strategy: :aggressive)

      expect(out).to include('# @api public')
    end
  end

  describe 'context' do
    it 'receives correct visibility and container' do
      received = []

      spy = Class.new(Docscribe::Plugin::Base::TagPlugin) do
        define_method(:call) do |context|
          received << context
          []
        end
      end.new

      Docscribe::Plugin::Registry.register(spy)

      code = <<~RUBY
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

      rewrite(code)

      containers   = received.map(&:container).uniq
      visibilities = received.map(&:visibility)

      expect(containers).to eq(['MyService'])
      expect(visibilities).to include(:public, :private)
    end
  end
end
