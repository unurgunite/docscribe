# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS integration' do
  before { skip_unless_rbs_available! }

  describe 'overrides inferred return type using RBS' do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs, config: conf) }

    let(:conf) { { 'emit' => { 'header' => true } } }
    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (verbose: bool, options: ::Hash[::Symbol, untyped]) -> ::Integer
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(verbose: true, options: {})
            "a"
          end
        end
      RUBY
    end

    it 'overrides inferred return type using RBS (String body, Integer in RBS)' do
      # If RBS was ignored, inference would produce String here.
      expect(out).to include('# +Demo#foo+ -> Integer')
      expect(out).to match(header_regex('Demo', 'foo', 'Integer'))
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')

      # Param types should also come from RBS when available.
      expect(out).to include(param_tag('verbose', 'Boolean'))

      # Your formatter currently keeps generics, so Hash[Symbol, untyped] becomes Hash<Symbol, Object>.
      # If you later decide to "collapse generics", change this expectation accordingly.
      expect(out).to include(param_tag('options', 'Hash<Symbol, Object>'))
    end
  end

  describe 'overrides required keyword-without-default type using RBS' do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (verbose: bool, options: ::Hash[::Symbol, untyped]) -> ::Integer
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(verbose:, options: {})
            "a"
          end
        end
      RUBY
    end

    it 'overrides required keyword-without-default type using RBS (Object by inference, Boolean by RBS)' do
      # Without RBS, "verbose:" (no default) is inferred as Object.
      expect(out).to include(param_tag('verbose', 'Boolean'))
      expect(out).not_to include(param_tag('verbose', 'Object'))

      # Without RBS, return would be String; with RBS it must be Integer.
      expect(out).to include('# @return [Integer]')
      expect(out).not_to include('# @return [String]')
    end
  end

  context 'when sig_dir has nested collection-like structure' do
    it 'resolves types from nested subdirectories' do
      # .gem_rbs_collection/my_gem/1.0/my_gem.rbs
      Dir.mktmpdir do |root|
        nested = File.join(root, 'my_gem', '1.0')
        FileUtils.mkdir_p(nested)
        File.write(File.join(nested, 'my_gem.rbs'), <<~RBS)
          class MyGemClass
            def process: (String input) -> Integer
          end
        RBS

        provider = Docscribe::Types::RBS::Provider.new(sig_dirs: [root])
        sig = provider.signature_for(container: 'MyGemClass', scope: :instance, name: :process)

        expect(sig).not_to be_nil
        expect(sig.return_type).to eq('Integer')
        expect(sig.param_types['input']).to eq('String')
      end
    end
  end

  describe 'safe mode with RBS type mismatch' do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (Integer x) -> Integer
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @param [String] x custom type
          # @return [String]
          def foo(x)
            x.to_s
          end
        end
      RUBY
    end

    it 'keeps existing [String] param type instead of overwriting with [Integer] from RBS' do
      expect(out).to include(param_tag('x', 'String', description: 'custom type'))
      expect(out).not_to include(param_tag('x', 'Integer'))
    end

    it 'keeps existing [String] return type instead of overwriting with [Integer] from RBS' do
      expect(out).to include('# @return [String]')
      expect(out).not_to include('# @return [Integer]')
    end
  end

  describe 'aggressive mode with RBS' do
    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (Integer x) -> Integer
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @param [String] x custom type
          # @return [String]
          def foo(x)
            x.to_s
          end
        end
      RUBY
    end

    it 'updates param type from RBS in aggressive mode' do
      Dir.mktmpdir do |dir|
        sig_dir = File.join(dir, 'sig')
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        config = Docscribe::Config.new(
          'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] }
        )

        result = Docscribe::InlineRewriter.rewrite_with_report(
          code, strategy: :aggressive, config: config, file: 'test.rb'
        )
        expect(result[:output]).to include(param_tag('x', 'Integer'))
        expect(result[:output]).not_to include(param_tag('x', 'String'))
      end
    end

    it 'updates return type from RBS in aggressive mode' do
      Dir.mktmpdir do |dir|
        sig_dir = File.join(dir, 'sig')
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        config = Docscribe::Config.new(
          'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] }
        )

        result = Docscribe::InlineRewriter.rewrite_with_report(
          code, strategy: :aggressive, config: config, file: 'test.rb'
        )
        expect(result[:output]).to include('# @return [Integer]')
        expect(result[:output]).not_to include('# @return [String]')
      end
    end
  end

  describe 'rewrite_with_report detects type mismatches in safe mode with RBS' do
    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (Integer x) -> Integer
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          # Documentation
          #
          # @param [String] x custom type
          # @return [String]
          def foo(x)
            x.to_s
          end
        end
      RUBY
    end

    it 'includes updated_param in changes when RBS type differs' do
      Dir.mktmpdir do |dir|
        sig_dir = File.join(dir, 'sig')
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        config = Docscribe::Config.new(
          'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] }
        )

        result = Docscribe::InlineRewriter.rewrite_with_report(
          code, strategy: :safe, config: config, file: 'test.rb'
        )

        updated_params = result[:changes].select { |c| c[:type] == :updated_param }
        expect(updated_params.size).to eq(1)
        expect(updated_params.first[:message]).to include('x')
        expect(updated_params.first[:message]).to include('String')
        expect(updated_params.first[:message]).to include('Integer')
      end
    end

    it 'includes updated_return in changes when RBS return type differs' do
      Dir.mktmpdir do |dir|
        sig_dir = File.join(dir, 'sig')
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), rbs)

        config = Docscribe::Config.new(
          'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] }
        )

        result = Docscribe::InlineRewriter.rewrite_with_report(
          code, strategy: :safe, config: config, file: 'test.rb'
        )

        updated_returns = result[:changes].select { |c| c[:type] == :updated_return }
        expect(updated_returns.size).to eq(1)
        expect(updated_returns.first[:message]).to include('String')
        expect(updated_returns.first[:message]).to include('Integer')
      end
    end
  end
end
