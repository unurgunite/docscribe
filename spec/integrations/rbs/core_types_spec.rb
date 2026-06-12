# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe Docscribe::InlineRewriter do
  describe 'resolves Numeric#positive? from core RBS via rbs collection pattern' do
    subject(:methods) { builder.build_instance(RBS::TypeName.parse('::Numeric')) }

    let(:root) { Dir.mktmpdir }
    let(:sig_dir) { File.join(root, 'sig') }

    let(:loader) do
      RBS::EnvironmentLoader.new.tap do |l|
        l.add(library: 'rbs')
        l.add(path: Pathname(sig_dir))
      end
    end

    let(:env) { RBS::Environment.from_loader(loader).resolve_type_names }
    let(:builder) { RBS::DefinitionBuilder.new(env: env) }

    before do
      skip_unless_rbs_available!
      FileUtils.mkdir_p(sig_dir)
      File.write(File.join(sig_dir, 'demo.rbs'), <<~RBS)
        class Demo
          def foo: () -> String
        end
      RBS
    end

    after { FileUtils.rm_rf(root) }

    it 'has positive? method' do
      expect(methods.methods[:positive?]).not_to be_nil
    end

    it 'has at least one type signature' do
      expect(methods.methods[:positive?].method_types.length).to be > 0
    end

    it 'returns Function type' do
      method_type = methods.methods[:positive?].method_types.first
      expect(method_type.type).to be_a(RBS::Types::Function)
    end

    it 'returns Bool' do
      method_type = methods.methods[:positive?].method_types.first
      expect(method_type.type.return_type).to be_a(RBS::Types::Bases::Bool)
    end
  end

  describe 'does NOT resolve Numeric when core_root is nil' do
    subject(:build) { builder.build_instance(RBS::TypeName.parse('::Numeric')) }

    let(:root) { Dir.mktmpdir }
    let(:sig_dir) { File.join(root, 'sig') }

    let(:loader) do
      RBS::EnvironmentLoader.new(core_root: nil).tap { |l| l.add(path: Pathname(sig_dir)) }
    end

    let(:env) { RBS::Environment.from_loader(loader).resolve_type_names }
    let(:builder) { RBS::DefinitionBuilder.new(env: env) }

    before do
      skip_unless_rbs_available!
      FileUtils.mkdir_p(sig_dir)
    end

    after { FileUtils.rm_rf(root) }

    it 'raises Unknown name error' do
      expect { build }.to raise_error(RuntimeError, /Unknown name/)
    end
  end
end
