# frozen_string_literal: true

RSpec.describe 'Sorbet inline signature integration' do
  def skip_unless_sorbet_bridge_available!
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    skip 'RubyVM::AbstractSyntaxTree not available' unless defined?(RubyVM::AbstractSyntaxTree)
  end

  def inline_with_sorbet(code, config_overrides = {})
    skip_unless_sorbet_bridge_available!

    raw = {
      'sorbet' => {
        'enabled' => true
      }
    }

    raw.merge!(config_overrides)

    Docscribe::InlineRewriter.insert_comments(
      code,
      config: Docscribe::Config.new(raw)
    )
  end

  it 'uses inline single-line sigs for params and return types' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { params(verbose: T::Boolean, count: Integer).returns(Integer) }
        def foo(verbose:, count:)
          "a"
        end
      end
    RUBY

    out = inline_with_sorbet(code)

    expect(out).to include('# +Demo#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [String]')

    expect(out).to include(param_tag('verbose', 'Boolean'))
    expect(out).to include(param_tag('count', 'Integer'))
    expect(out).not_to include(param_tag('verbose', 'Object'))
    expect(out).not_to include(param_tag('count', 'Object'))
  end

  it 'uses multiline sig do ... end signatures' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        sig do
          params(name: T.nilable(String))
            .returns(T.any(String, Integer))
        end
        def foo(name)
          "a"
        end
      end
    RUBY

    out = inline_with_sorbet(code)

    expect(out).to match(
      /# @param \[(?:String\?|String, nil|nil, String)\] name Param documentation\./
    )

    expect(out).to match(
      /# @return \[(?:String, Integer|Integer, String)\]/
    )
    expect(out).not_to include('# @return [String]')
  end

  it 'uses inline sigs for class methods' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { returns(Symbol) }
        def self.status
          "ok"
        end
      end
    RUBY

    out = inline_with_sorbet(code)

    expect(out).to include('# +Demo.status+ -> Symbol')
    expect(out).to include('# @return [Symbol]')
    expect(out).not_to include('# @return [String]')
  end

  it 'renders void returns from inline sigs' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { params(flag: T::Boolean).void }
        def foo(flag)
          123
        end
      end
    RUBY

    out = inline_with_sorbet(code)

    expect(out).to include('# +Demo#foo+ -> void')
    expect(out).to include('# @return [void]')
    expect(out).to include(param_tag('flag', 'Boolean'))
    expect(out).not_to include('# @return [Integer]')
  end

  it 'uses Sorbet rest arg and kwrest element types' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { params(args: Integer, kwargs: Float).returns(Symbol) }
        def foo(*args, **kwargs)
          :ok
        end
      end
    RUBY

    out = inline_with_sorbet(code)

    expect(out).to include(param_tag('args', 'Array<Integer>'))
    expect(out).to include(param_tag('kwargs', 'Hash<Symbol, Float>'))
    expect(out).to include('# @return [Symbol]')
  end
end
