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

  describe 'handles unnamed positional parameters in RBS (by position matching)' do
    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (String, Integer) -> String
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(a, b)
            a
          end
        end
      RUBY
    end

    describe 'safe mode infers param types by position from unnamed RBS params' do
      subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

      it { is_expected.to include(param_tag('a', 'String')) }
      it { is_expected.to include(param_tag('b', 'Integer')) }
      it { is_expected.not_to include(param_tag('a', 'Object')) }
      it { is_expected.not_to include(param_tag('b', 'Object')) }
    end

    describe 'aggressive mode applies param types by position from unnamed RBS params' do
      subject(:result) do
        Dir.mktmpdir do |dir|
          sig_dir = File.join(dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'demo.rbs'), rbs)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          described_class.rewrite_with_report(code, strategy: :aggressive, config: config, file: 'test.rb')
        end
      end

      it { expect(result[:output]).to include(param_tag('a', 'String')) }
      it { expect(result[:output]).to include(param_tag('b', 'Integer')) }
      it { expect(result[:output]).not_to include(param_tag('a', 'Object')) }
      it { expect(result[:output]).not_to include(param_tag('b', 'Object')) }
    end
  end

  describe 'handles mix of named and unnamed positional parameters in RBS' do
    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (String, Integer y) -> String
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(x, y)
            x
          end
        end
      RUBY
    end

    describe 'safe mode uses position for unnamed and name for named params' do
      subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

      it { is_expected.to include(param_tag('x', 'String')) }
      it { is_expected.to include(param_tag('y', 'Integer')) }
      it { is_expected.not_to include(param_tag('x', 'Object')) }
      it { is_expected.not_to include(param_tag('y', 'Object')) }
    end

    describe 'aggressive mode uses position for unnamed and name for named params' do
      subject(:result) do
        Dir.mktmpdir do |dir|
          sig_dir = File.join(dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'demo.rbs'), rbs)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          described_class.rewrite_with_report(code, strategy: :aggressive, config: config, file: 'test.rb')
        end
      end

      it { expect(result[:output]).to include(param_tag('x', 'String')) }
      it { expect(result[:output]).to include(param_tag('y', 'Integer')) }
      it { expect(result[:output]).not_to include(param_tag('x', 'Object')) }
      it { expect(result[:output]).not_to include(param_tag('y', 'Object')) }
    end
  end

  describe 'handles only unnamed params in RBS (no named params at all)' do
    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (Array[String], Hash[Symbol, Integer]) -> Array[Integer]
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(items, options)
            items.map { |x| x.to_i }
          end
        end
      RUBY
    end

    describe 'safe mode applies complex generic types by position for unnamed params' do
      subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

      it { is_expected.to include(param_tag('items', 'Array<String>')) }
      it { is_expected.to include(param_tag('options', 'Hash<Symbol, Integer>')) }
      it { is_expected.not_to include(param_tag('items', 'Object')) }
      it { is_expected.not_to include(param_tag('options', 'Object')) }
    end

    describe 'aggressive mode applies complex generic types by position for unnamed params' do
      subject(:result) do
        Dir.mktmpdir do |dir|
          sig_dir = File.join(dir, 'sig')
          FileUtils.mkdir_p(sig_dir)
          File.write(File.join(sig_dir, 'demo.rbs'), rbs)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
          described_class.rewrite_with_report(code, strategy: :aggressive, config: config, file: 'test.rb')
        end
      end

      it { expect(result[:output]).to include(param_tag('items', 'Array<String>')) }
      it { expect(result[:output]).not_to include(param_tag('items', 'Object')) }
    end
  end

  describe 'uses named param_types over positional when both are available' do
    subject(:out) { inline_with_rbs(code: code, rbs: rbs) }

    let(:rbs) do
      <<~RBS
        class Demo
          def foo: (String, Integer y) -> String
        end
      RBS
    end

    let(:code) do
      <<~RUBY
        class Demo
          def foo(x, y)
            x
          end
        end
      RUBY
    end

    it 'resolves y to Integer (named) and x to String (positional)' do
      expect(out).to include(param_tag('x', 'String')).and include(param_tag('y', 'Integer'))
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
