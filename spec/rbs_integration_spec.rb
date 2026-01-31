# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS integration' do
  def inline_with_rbs(code:, rbs:, sig_dir_name: 'sig')
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    Dir.mktmpdir do |dir|
      sig_dir = File.join(dir, sig_dir_name)
      FileUtils.mkdir_p(sig_dir)

      File.write(File.join(sig_dir, 'demo.rbs'), rbs)

      conf = Docscribe::Config.new(
        'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] }
      )

      Docscribe::InlineRewriter.insert_comments(code, config: conf)
    end
  end

  it 'overrides inferred return type using RBS (String body, Integer in RBS)' do
    rbs = <<~RBS
      class Demo
        def foo: (verbose: bool, options: ::Hash[::Symbol, untyped]) -> ::Integer
      end
    RBS

    code = <<~RUBY
      class Demo
        def foo(verbose: true, options: {})
          "a"
        end
      end
    RUBY

    out = inline_with_rbs(code: code, rbs: rbs)

    # If RBS was ignored, inference would produce String here.
    expect(out).to include('# +Demo#foo+ -> Integer')
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [String]')

    # Param types should also come from RBS when available.
    expect(out).to include('# @param [Boolean] verbose')

    # Your formatter currently keeps generics, so Hash[Symbol, untyped] becomes Hash<Symbol, Object>.
    # If you later decide to "collapse generics", change this expectation accordingly.
    expect(out).to include('# @param [Hash<Symbol, Object>] options')
  end

  it 'overrides required keyword-without-default type using RBS (Object by inference, Boolean by RBS)' do
    rbs = <<~RBS
      class Demo
        def foo: (verbose: bool, options: ::Hash[::Symbol, untyped]) -> ::Integer
      end
    RBS

    code = <<~RUBY
      class Demo
        def foo(verbose:, options: {})
          "a"
        end
      end
    RUBY

    out = inline_with_rbs(code: code, rbs: rbs)

    # Without RBS, "verbose:" (no default) is inferred as Object.
    expect(out).to include('# @param [Boolean] verbose')
    expect(out).not_to include('# @param [Object] verbose')

    # Without RBS, return would be String; with RBS it must be Integer.
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [String]')
  end
end
