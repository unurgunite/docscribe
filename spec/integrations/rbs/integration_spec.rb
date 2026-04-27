# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS integration' do
  before { skip_unless_rbs_available! }

  describe 'overrides inferred return type using RBS' do
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
          def foo(verbose: true, options: {})
            "a"
          end
        end
      RUBY
    end

    it 'overrides inferred return type using RBS (String body, Integer in RBS)' do
      # If RBS was ignored, inference would produce String here.
      expect(out).to include('# +Demo#foo+ -> Integer')
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
end
