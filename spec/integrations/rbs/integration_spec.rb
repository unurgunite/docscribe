# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe Docscribe::InlineRewriter do
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

    it { is_expected.to include('# +Demo#foo+ -> Integer') }
    it { is_expected.to match(header_regex('Demo', 'foo', 'Integer')) }
    it { is_expected.to include('# @return [Integer]') }
    it { is_expected.not_to include('# @return [String]') }
    it { is_expected.to include(param_tag('verbose', 'Boolean')) }
    it { is_expected.to include(param_tag('options', 'Hash<Symbol, Object>')) }
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

    it { is_expected.to include(param_tag('verbose', 'Boolean')) }
    it { is_expected.not_to include(param_tag('verbose', 'Object')) }
    it { is_expected.to include('# @return [Integer]') }
    it { is_expected.not_to include('# @return [String]') }
  end

  context 'when sig_dir has nested collection-like structure' do
    let(:root) { Dir.mktmpdir }
    let(:nested) { File.join(root, 'my_gem', '1.0') }
    let(:rbs_path) { File.join(nested, 'my_gem.rbs') }

    before do
      FileUtils.mkdir_p(nested)
      File.write(rbs_path, <<~RBS)
        class MyGemClass
          def process: (String input) -> Integer
        end
      RBS
    end

    after { FileUtils.rm_rf(root) }

    describe 'resolves types from nested subdirectories' do
      subject(:sig) { Docscribe::Types::RBS::Provider.new(sig_dirs: [root]).signature_for(container: 'MyGemClass', scope: :instance, name: :process) }

      it { is_expected.not_to be_nil }
      it { expect(sig.return_type).to eq('Integer') }
      it { expect(sig.param_types['input']).to eq('String') }
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

    it { is_expected.to include(param_tag('x', 'String', description: 'custom type')) }
    it { is_expected.not_to include(param_tag('x', 'Integer')) }
    it { is_expected.to include('# @return [String]') }
    it { is_expected.not_to include('# @return [Integer]') }
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

    describe 'updates param type from RBS in aggressive mode' do
      subject(:result) do
        Dir.mktmpdir do |dir|
          sig_dir = File.join(dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'demo.rbs'), rbs)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          described_class.rewrite_with_report(code, strategy: :aggressive, config: config, file: 'test.rb')
        end
      end

      it { expect(result[:output]).to include(param_tag('x', 'Integer')) }
      it { expect(result[:output]).not_to include(param_tag('x', 'String')) }
    end

    describe 'updates return type from RBS in aggressive mode' do
      subject(:result) do
        Dir.mktmpdir do |dir|
          sig_dir = File.join(dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'demo.rbs'), rbs)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          described_class.rewrite_with_report(code, strategy: :aggressive, config: config, file: 'test.rb')
        end
      end

      it { expect(result[:output]).to include('# @return [Integer]') }
      it { expect(result[:output]).not_to include('# @return [String]') }
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

    describe 'includes updated_param in changes when RBS type differs' do
      subject(:result) do
        Dir.mktmpdir do |dir|
          sig_dir = File.join(dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'demo.rbs'), rbs)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          described_class.rewrite_with_report(code, strategy: :safe, config: config, file: 'test.rb')
        end
      end

      it :aggregate_failures do
        updated_params = result[:changes].select { |c| c[:type] == :updated_param }
        expect(updated_params.size).to eq(1)
        expect(updated_params.first[:message]).to include('x')
        expect(updated_params.first[:message]).to include('String')
        expect(updated_params.first[:message]).to include('Integer')
      end
    end

    describe 'includes updated_return in changes when RBS return type differs' do
      subject(:result) do
        Dir.mktmpdir do |dir|
          sig_dir = File.join(dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'demo.rbs'), rbs)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          described_class.rewrite_with_report(code, strategy: :safe, config: config, file: 'test.rb')
        end
      end

      it :aggregate_failures do
        updated_returns = result[:changes].select { |c| c[:type] == :updated_return }
        expect(updated_returns.size).to eq(1)
        expect(updated_returns.first[:message]).to include('String')
        expect(updated_returns.first[:message]).to include('Integer')
      end
    end
  end
end
