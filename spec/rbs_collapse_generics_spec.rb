# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS collapse_generics option' do
  def inline_with_rbs(code:, rbs:, collapse_generics:)
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    Dir.mktmpdir do |dir|
      sig_dir = File.join(dir, 'sig')
      FileUtils.mkdir_p(sig_dir)

      File.write(File.join(sig_dir, 'demo.rbs'), rbs)

      conf = Docscribe::Config.new(
        'rbs' => {
          'enabled' => true,
          'sig_dirs' => [sig_dir],
          'collapse_generics' => collapse_generics
        }
      )

      Docscribe::InlineRewriter.insert_comments(code, config: conf)
    end
  end

  let(:rbs) do
    <<~RBS
      class Demo
        def foo: (options: ::Hash[::Symbol, untyped]) -> ::Integer
      end
    RBS
  end

  let(:code) do
    <<~RUBY
      class Demo
        def foo(options: {})
          "a"
        end
      end
    RUBY
  end

  it 'keeps generics when rbs.collapse_generics is false' do
    out = inline_with_rbs(code: code, rbs: rbs, collapse_generics: false)

    # Prove RBS is actually used (otherwise inference would be String)
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [String]')

    # And generics should be preserved
    expect(out).to include('# @param [Hash<Symbol, Object>] options')
  end

  it 'collapses generics when rbs.collapse_generics is true' do
    out = inline_with_rbs(code: code, rbs: rbs, collapse_generics: true)

    # Prove RBS is actually used
    expect(out).to include('# @return [Integer]')
    expect(out).not_to include('# @return [String]')

    # Generics collapsed
    expect(out).to include('# @param [Hash] options')
    expect(out).not_to include('# @param [Hash<Symbol, Object>] options')
  end
end
