# frozen_string_literal: true

RSpec.describe 'Sorbet-aware doc anchoring' do
  def skip_unless_sorbet_bridge_available!
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    skip 'RubyVM::AbstractSyntaxTree not available' unless defined?(RubyVM::AbstractSyntaxTree)
  end

  def inline_with_sorbet(code, strategy: :safe)
    skip_unless_sorbet_bridge_available!

    conf = Docscribe::Config.new(
      'sorbet' => {
        'enabled' => true
      }
    )

    Docscribe::InlineRewriter.insert_comments(
      code,
      strategy: strategy,
      config: conf
    )
  end

  it 'merges into an existing doc block above sig instead of inserting a second block' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        # Existing docs
        # @return [Integer]
        sig { params(verbose: T::Boolean).returns(Integer) }
        def foo(verbose:)
          "a"
        end
      end
    RUBY

    out = inline_with_sorbet(code, strategy: :safe)

    expect(out).to include('# Existing docs')
    expect(out).to include('# @return [Integer]')
    expect(out).to include(param_tag('verbose', 'Boolean'))
    expect(out).not_to include('# +Demo#foo+')
    expect(out.scan(/# @return \[Integer\]/).length).to eq(1)
  end

  it 'detects a legacy doc block between sig and def and does not duplicate it' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { params(verbose: T::Boolean).returns(Integer) }
        # Existing docs
        # @return [Integer]
        def foo(verbose:)
          "a"
        end
      end
    RUBY

    out = inline_with_sorbet(code, strategy: :safe)

    expect(out).to include('# Existing docs')
    expect(out).to include(param_tag('verbose', 'Boolean'))
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# +Demo#foo+')
    expect(out.scan(/# @return \[Integer\]/).length).to eq(1)
  end

  it 'inserts newly generated docs above sig for undocumented Sorbet methods' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { params(verbose: T::Boolean).returns(Integer) }
        def foo(verbose:)
          "a"
        end
      end
    RUBY

    out = inline_with_sorbet(code, strategy: :safe)

    expect(out).to match(
      /# \+Demo#foo\+ -> Integer.*?\n\s*# @param \[Boolean\] verbose Param documentation\.\n\s*# @return \[Integer\]\n\s*sig \{ params\(verbose: T::Boolean\)\.returns\(Integer\) \}\n\s*def foo\(verbose:\)/m
    )
  end

  it 'aggressive mode removes and rebuilds a doc block above sig' do
    code = <<~RUBY
      class Demo
        extend T::Sig

        # Wrong docs
        # @return [String]
        sig { params(verbose: T::Boolean).returns(Integer) }
        def foo(verbose:)
          "a"
        end
      end
    RUBY

    out = inline_with_sorbet(code, strategy: :aggressive)

    expect(out).to include('# +Demo#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [String]')

    expect(out).to match(
      /# \+Demo#foo\+ -> Integer.*?\n\s*sig \{ params\(verbose: T::Boolean\)\.returns\(Integer\) \}\n\s*def foo\(verbose:\)/m
    )
  end
end
