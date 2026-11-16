# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'docscribe/inline_rewriter'
require 'docscribe/config'

RSpec.describe Docscribe::InlineRewriter do
  subject(:result) do
    described_class.rewrite_with_report(code, strategy: :safe, config: config, file: 'test.rb')
  end

  let(:config) { Docscribe::Config.new('validate_types' => validate) }
  let(:validate) { false }

  describe 'return mismatch' do
    context 'without validate_types' do
      let(:validate) { false }
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end

      it 'does not report mismatch' do
        expect(result[:changes].any? { |c| c[:type] == :updated_return }).to be false
      end
    end

    context 'with validate_types' do
      let(:validate) { true }
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end

      it 'reports updated_return', :aggregate_failures do
        updated = result[:changes].select { |c| c[:type] == :updated_return }
        expect(updated.size).to eq(1)
        expect(updated.first[:message]).to include('Integer').and include('String')
      end
    end

    context 'when inferred is Object fallback' do
      let(:validate) { true }
      let(:code) do
        <<~RUBY
          class Foo
            # @return [String]
            def bar
              unknown_method
            end
          end
        RUBY
      end

      it 'silences mismatch' do
        expect(result[:changes].any? { |c| c[:type] == :updated_return }).to be false
      end
    end
  end

  describe 'invalid syntax' do
    let(:code) do
      <<~RUBY
        class Foo
          # @return [Sym bol]
          def bar
            :x
          end
        end
      RUBY
    end

    it 'reports invalid_type even without validate_types' do
      expect(result[:changes].select { |c| c[:type] == :invalid_type }.size).to eq(1)
    end

    it 'provides corrected line for safe fix Sym bol -> Symbol', :aggregate_failures do
      expect(result[:output]).to include('@return [Symbol]')
      expect(result[:output]).not_to include('Sym bol')
    end
  end

  describe 'invalid syntax Objec3t' do
    let(:code) do
      <<~RUBY
        class Foo
          # @return [Objec3t]
          def bar
            Object.new
          end
        end
      RUBY
    end

    it 'provides corrected line for safe fix Objec3t -> Object', :aggregate_failures do
      expect(result[:output]).to include('@return [Object]')
      expect(result[:output]).not_to include('Objec3t')
    end
  end

  describe 'param mismatch' do
    let(:validate) { true }
    let(:code) do
      <<~RUBY
        class Foo
          # @param [String] x
          # @return [Object]
          def bar(x: 123)
            x
          end
        end
      RUBY
    end

    it 'reports updated_param', :aggregate_failures do
      updated = result[:changes].select { |c| c[:type] == :updated_param }
      expect(updated.size).to eq(1)
      expect(updated.first[:message]).to include('x')
    end
  end

  describe 'param invalid syntax' do
    let(:code) do
      <<~RUBY
        class Foo
          # @param [Sym bol] x
          # @return [Symbol]
          def bar(x = :sym)
            x
          end
        end
      RUBY
    end

    it 'provides corrected line for safe fix', :aggregate_failures do
      expect(result[:output]).to include('@param [Symbol] x')
      expect(result[:output]).not_to include('Sym bol')
    end
  end

  describe 'warn_invalid_yard toggle' do
    let(:code) do
      <<~RUBY
        class Foo
          # @param [Sym bol] x
          # @return [Sy mbol]
          def bar(x = :sym)
            x
          end
        end
      RUBY
    end

    context 'when enabled (default)' do
      it 'reports both param and return invalid types', :aggregate_failures do
        invalid = result[:changes].select { |c| c[:type] == :invalid_type }
        expect(invalid.size).to eq(2)
        expect(invalid.map { |c| c[:source] }.uniq).to eq(['syntax'])
      end

      it 'still applies the safe fix', :aggregate_failures do
        expect(result[:output]).to include('@param [Symbol] x')
        expect(result[:output]).to include('@return [Symbol]')
      end
    end

    context 'when disabled' do
      let(:config) { Docscribe::Config.new('warn_invalid_yard' => false) }

      it 'stays quiet about broken syntax' do
        expect(result[:changes].any? { |c| c[:type] == :invalid_type }).to be false
      end

      it 'leaves the broken types untouched' do
        expect(result[:output]).to include('Sym bol')
      end
    end

    context 'when disabled but validate_types enabled' do
      let(:config) { Docscribe::Config.new('warn_invalid_yard' => false, 'validate_types' => true) }

      it 'still stays quiet about broken syntax' do
        expect(result[:changes].any? { |c| c[:type] == :invalid_type }).to be false
      end
    end
  end

  describe 'param type without type information' do
    shared_examples 'a flagged empty type' do
      it 'reports invalid_type with syntax source', :aggregate_failures do
        invalid = result[:changes].select { |c| c[:type] == :invalid_type }
        expect(invalid.size).to eq(1)
        expect(invalid.first[:source]).to eq('syntax')
        expect(invalid.first[:message]).to include("invalid YARD type [#{literal}] for @param x")
      end
    end

    ['[]', '[ ]', '[:sym]'].each do |doc_type|
      context "when the @param type is #{doc_type}" do
        let(:literal) { doc_type[/\[(.*)\]/, 1] }
        let(:code) do
          <<~RUBY
            class Foo
              # @param #{doc_type} x
              # @return [String]
              def bar(x)
                x
              end
            end
          RUBY
        end

        it_behaves_like 'a flagged empty type'
      end
    end

    context 'when validate_types is disabled' do
      let(:validate) { false }
      let(:code) do
        <<~RUBY
          class Foo
            # @param [] x
            # @return [String]
            def bar(x)
              x
            end
          end
        RUBY
      end

      it 'still reports invalid_type' do
        expect(result[:changes].any? { |c| c[:type] == :invalid_type }).to be true
      end
    end

    context 'when the type has surrounding spaces' do
      let(:code) do
        <<~RUBY
          class Foo
            # @param [ String ] x
            # @return [String]
            def bar(x)
              x
            end
          end
        RUBY
      end

      it 'is not flagged' do
        expect(result[:changes].none? { |c| c[:type] == :invalid_type }).to be true
      end
    end

    context 'when the @param literal appears alongside a missing @return' do
      let(:code) do
        <<~RUBY
          class Foo
            # @param [] x
            def bar(x)
              x
            end
          end
        RUBY
      end

      it 'reports both offenses', :aggregate_failures do
        types = result[:changes].map { |c| c[:type] }
        expect(types).to include(:invalid_type)
        expect(types).to include(:missing_return)
      end
    end
  end

  describe 'source field' do
    context 'with syntax source for invalid YARD' do
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Sym bol]
            def bar
              :x
            end
          end
        RUBY
      end
      let(:config) { Docscribe::Config.new('validate_types' => true) }

      it 'reports syntax source' do
        expect(result[:changes].first[:source]).to eq('syntax')
      end
    end

    context 'with infer source for mismatch without RBS' do
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end
      let(:config) { Docscribe::Config.new('validate_types' => true) }

      it 'reports infer source' do
        expect(result[:changes].first[:source]).to eq('infer')
      end
    end

    context 'with rbs source when RBS type differs' do
      let(:code) do
        <<~RUBY
          class Foo
            # @return [Integer]
            def bar
              "hello"
            end
          end
        RUBY
      end
      let(:tmp_dir) { Dir.mktmpdir }
      let(:sig_dir) do
        dir = File.join(tmp_dir, 'sig')
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'foo.rbs'), "class Foo\n  def bar: () -> String\nend\n")
        dir
      end
      let(:rbs_config) do
        Docscribe::Config.new('validate_types' => true, 'rbs' => { 'enabled' => true, 'sig_dirs' => [sig_dir] })
      end
      let(:rbs_result) do
        described_class.rewrite_with_report(code, strategy: :safe, config: rbs_config, file: 'test.rb')
      end

      after { FileUtils.remove_entry(tmp_dir) }

      it 'reports rbs source' do
        skip_unless_rbs_available!
        expect(rbs_result[:changes].first[:source]).to eq('rbs')
      end
    end
  end
end
