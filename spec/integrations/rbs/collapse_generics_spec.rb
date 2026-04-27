# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS collapse_generics option' do
  before { skip_unless_rbs_available! }

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

  let(:collapse_generics) { false }

  describe 'when rbs.collapse_generics is false' do
    subject(:out) do
      Dir.mktmpdir do |dir|
        sig_dir = File.join(dir, 'sig')
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        inline(
          code,
          config: Docscribe::Config.new(
            'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir], 'collapse_generics' => collapse_generics }
          )
        )
      end
    end

    let(:collapse_generics) { false }

    it 'keeps generics' do
      # Prove RBS is actually used (otherwise inference would be String)
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')

      # And generics should be preserved
      expect(out).to include(param_tag('options', 'Hash<Symbol, Object>'))
    end
  end

  describe 'when rbs.collapse_generics is true' do
    subject(:out) do
      Dir.mktmpdir do |dir|
        sig_dir = File.join(dir, 'sig')
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        inline(
          code,
          config: Docscribe::Config.new(
            'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir], 'collapse_generics' => collapse_generics }
          )
        )
      end
    end

    let(:collapse_generics) { true }

    it 'collapses generics' do
      # Prove RBS is actually used
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')

      # Generics collapsed
      expect(out).to include(param_tag('options', 'Hash'))
      expect(out).not_to include(param_tag('options', 'Hash<Symbol, Object>'))
    end
  end
end
