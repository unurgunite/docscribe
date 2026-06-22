# frozen_string_literal: true

require 'tmpdir'

RSpec.describe 'Docscribe::Types::RBS::Provider' do
  before do
    skip_unless_rbs_available!
    require 'docscribe/types/rbs/provider'
  end

  let(:provider) { Docscribe::Types::RBS::Provider.new(sig_dirs: []) }

  describe '#definition_for' do
    before { provider.signature_for(container: 'Integer', scope: :instance, name: :to_s) }

    it 'strips YARD-style generic params (Array<String> -> Array)' do
      result = provider.send(:definition_for, container: 'Array<String>', scope: :instance)
      expect(result).not_to be_nil
    end

    it 'strips RBS-style generic params (Array[String] -> Array)' do
      result = provider.send(:definition_for, container: 'Array[String]', scope: :instance)
      expect(result).not_to be_nil
    end

    it 'returns nil for unknown type names' do
      result = provider.send(:definition_for, container: 'NonExistentFooBar', scope: :instance)
      expect(result).to be_nil
    end

    it 'works for plain class names' do
      result = provider.send(:definition_for, container: 'Integer', scope: :instance)
      expect(result).not_to be_nil
    end

    it 'handles nested generic params (Array[Array[String]] -> Array)' do
      result = provider.send(:definition_for, container: 'Array[Array[String]]', scope: :instance)
      expect(result).not_to be_nil
    end

    it 'handles singleton scope' do
      result = provider.send(:definition_for, container: 'String', scope: :class)
      expect(result).not_to be_nil
    end

    it 'returns nil for unknown singleton scope' do
      result = provider.send(:definition_for, container: 'NonExistentFooBar', scope: :class)
      expect(result).to be_nil
    end
  end

  describe '#signature_for' do
    context 'with a custom RBS class' do
      let(:root) { Dir.mktmpdir }
      let(:sig_dir) { File.join(root, 'sig') }
      let(:provider) { Docscribe::Types::RBS::Provider.new(sig_dirs: [sig_dir]) }

      before do
        FileUtils.mkdir_p(sig_dir)
        File.write(File.join(sig_dir, 'demo.rbs'), <<~RBS)
          class Demo
            def foo: (Array[String] items, Hash[Symbol, Integer] options) -> Array[Integer]
          end
        RBS
      end

      after { FileUtils.rm_rf(root) }

      it 'resolves a signature for a known class', :aggregate_failures do
        sig = provider.signature_for(container: 'Demo', scope: :instance, name: :foo)
        expect(sig).not_to be_nil
        expect(sig.param_types['items']).to eq('Array<String>')
        expect(sig.param_types['options']).to eq('Hash<Symbol, Integer>')
      end

      it 'resolves signature with YARD-style generic container name' do
        sig = provider.signature_for(container: 'Demo<String>', scope: :instance, name: :foo)
        expect(sig).not_to be_nil
      end

      it 'returns nil for unknown methods on known class' do
        sig = provider.signature_for(container: 'Demo', scope: :instance, name: :bar)
        expect(sig).to be_nil
      end

      it 'returns nil for unknown container' do
        sig = provider.signature_for(container: 'NonExistent', scope: :instance, name: :foo)
        expect(sig).to be_nil
      end
    end

    context 'with core stdlib types' do
      let(:provider) { Docscribe::Types::RBS::Provider.new(sig_dirs: []) }

      it 'resolves Array#map' do
        sig = provider.signature_for(container: 'Array', scope: :instance, name: :map)
        expect(sig).not_to be_nil
      end

      it 'resolves Array#map with YARD-style generic container' do
        sig = provider.signature_for(container: 'Array<String>', scope: :instance, name: :map)
        expect(sig).not_to be_nil
      end

      it 'resolves Array#map with RBS-style generic container' do
        sig = provider.signature_for(container: 'Array[Integer]', scope: :instance, name: :map)
        expect(sig).not_to be_nil
      end
    end
  end
end
