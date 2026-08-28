# frozen_string_literal: true

require 'docscribe/inline_rewriter'
require 'docscribe/config'

RSpec.describe 'validate_types integration' do
  def rewrite(code, validate: false, strategy: :safe)
    config = Docscribe::Config.new('validate_types' => validate)
    Docscribe::InlineRewriter.rewrite_with_report(code, strategy: strategy, config: config, file: 'test.rb')
  end

  it 'does not report mismatch without validate_types' do
    code = <<~RUBY
      class Foo
        # @return [Integer]
        def bar
          "hello"
        end
      end
    RUBY
    result = rewrite(code, validate: false)
    expect(result[:changes].any? { |c| c[:type] == :updated_return }).to be false
  end

  it 'reports updated_return with validate_types when Integer vs String' do
    code = <<~RUBY
      class Foo
        # @return [Integer]
        def bar
          "hello"
        end
      end
    RUBY
    result = rewrite(code, validate: true)
    updated = result[:changes].select { |c| c[:type] == :updated_return }
    expect(updated.size).to eq(1)
    expect(updated.first[:message]).to include('Integer').and include('String')
  end

  it 'reports invalid_type for Sym bol even without validate_types' do
    code = <<~RUBY
      class Foo
        # @return [Sym bol]
        def bar
          :x
        end
      end
    RUBY
    result = rewrite(code, validate: false)
    invalid = result[:changes].select { |c| c[:type] == :invalid_type }
    expect(invalid.size).to eq(1)
  end

  it 'silences when inferred is Object fallback' do
    code = <<~RUBY
      class Foo
        # @return [String]
        def bar
          unknown_method
        end
      end
    RUBY
    result = rewrite(code, validate: true)
    expect(result[:changes].any? { |c| c[:type] == :updated_return }).to be false
  end

  it 'reports param mismatch with validate_types' do
    code = <<~RUBY
      class Foo
        # @param [String] x
        # @return [Object]
        def bar(x: 123)
          x
        end
      end
    RUBY
    result = rewrite(code, validate: true)
    updated = result[:changes].select { |c| c[:type] == :updated_param }
    expect(updated.size).to eq(1)
    expect(updated.first[:message]).to include('x')
  end
end
