# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'Sorbet RBI integration' do
  def skip_unless_sorbet_bridge_available!
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    skip 'RubyVM::AbstractSyntaxTree not available' unless defined?(RubyVM::AbstractSyntaxTree)
  end

  def inline_with_signature_files(code:, rbi:, rbs: nil, rbi_dir_name: 'sorbet/rbi', sig_dir_name: 'sig')
    skip_unless_sorbet_bridge_available!

    Dir.mktmpdir do |dir|
      rbi_dir = File.join(dir, rbi_dir_name)
      FileUtils.mkdir_p(rbi_dir)
      File.write(File.join(rbi_dir, 'demo.rbi'), rbi)

      raw = {
        'sorbet' => {
          'enabled' => true,
          'rbi_dirs' => [rbi_dir]
        }
      }

      if rbs
        sig_dir = File.join(dir, sig_dir_name)
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        raw['rbs'] = {
          'enabled' => true,
          'sig_dirs' => [sig_dir]
        }
      end

      conf = Docscribe::Config.new(raw)
      Docscribe::InlineRewriter.insert_comments(code, config: conf)
    end
  end

  it 'uses RBI signatures for params and return types' do
    rbi = <<~RBI
      # typed: strict
      class Demo
        extend T::Sig

        sig { params(verbose: T::Boolean, count: Integer).returns(Integer) }
        def foo(verbose:, count:)
        end
      end
    RBI

    code = <<~RUBY
      class Demo
        def foo(verbose:, count:)
          "a"
        end
      end
    RUBY

    out = inline_with_signature_files(code: code, rbi: rbi)

    expect(out).to include('# +Demo#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [String]')

    expect(out).to include(param_tag('verbose', 'Boolean'))
    expect(out).to include(param_tag('count', 'Integer'))
    expect(out).not_to include(param_tag('verbose', 'Object'))
    expect(out).not_to include(param_tag('count', 'Object'))
  end

  it 'prefers RBI over RBS when both are present' do
    rbi = <<~RBI
      # typed: strict
      class Demo
        extend T::Sig

        sig { returns(Integer) }
        def foo
        end
      end
    RBI

    rbs = <<~RBS
      class Demo
        def foo: () -> Symbol
      end
    RBS

    code = <<~RUBY
      class Demo
        def foo
          "a"
        end
      end
    RUBY

    out = inline_with_signature_files(code: code, rbi: rbi, rbs: rbs)

    expect(out).to include('# +Demo#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [Symbol]')
    expect(out).not_to include('# @return [String]')
  end

  it 'falls back cleanly to inference when an RBI file cannot be parsed' do
    bad_rbi = <<~RBI
      class Demo
        extend T::Sig

        sig { params(x: Integer).returns( }
        def foo(x)
        end
      end
    RBI

    code = <<~RUBY
      class Demo
        def foo(x)
          "a"
        end
      end
    RUBY

    out = inline_with_signature_files(code: code, rbi: bad_rbi)

    expect(out).to include('# +Demo#foo+ -> String')
    expect(out).to include('# @return [String]')
    expect(out).to include(param_tag('x', 'Object'))
  end

  it 'prefers inline Sorbet sigs over RBI, RBS, and inference' do
    rbi = <<~RBI
      # typed: strict
      class Demo
        extend T::Sig

        sig { returns(Integer) }
        def foo
        end
      end
    RBI

    rbs = <<~RBS
      class Demo
        def foo: () -> Symbol
      end
    RBS

    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { returns(Float) }
        def foo
          "a"
        end
      end
    RUBY

    out = inline_with_signature_files(code: code, rbi: rbi, rbs: rbs)

    expect(out).to include('# +Demo#foo+ -> Float')
    expect(out).to include('# @return [Float]')
    expect(out).not_to include('# @return [Integer]')
    expect(out).not_to include('# @return [Symbol]')
    expect(out).not_to include('# @return [String]')
  end
end
