# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe 'RBS core types' do
  it 'resolves Numeric#positive? from core RBS via rbs collection pattern' do
    skip_unless_rbs_available!

    Dir.mktmpdir do |dir|
      sig_dir = File.join(dir, 'sig')
      FileUtils.mkdir_p(sig_dir)
      File.write(File.join(sig_dir, 'demo.rbs'), <<~RBS)
        class Demo
          def foo: () -> String
        end
      RBS

      # rbs collection pattern: add(library: 'rbs') loads core transitively
      loader = RBS::EnvironmentLoader.new
      loader.add(library: 'rbs')
      loader.add(path: Pathname(sig_dir))
      env = RBS::Environment.from_loader(loader).resolve_type_names
      builder = RBS::DefinitionBuilder.new(env: env)

      # build_instance returns Methods (not definition)
      methods = builder.build_instance(RBS::TypeName.parse('::Numeric'))
      defn = methods.methods[:positive?]

      expect(defn).not_to be_nil
      expect(defn.method_types.length).to be > 0

      # Check that the return type is bool
      method_type = defn.method_types.first
      func = method_type.type
      expect(func).to be_a(RBS::Types::Function)
      expect(func.return_type).to be_a(RBS::Types::Bases::Bool)
    end
  end

  it 'does NOT resolve Numeric when core_root is nil' do
    skip_unless_rbs_available!

    Dir.mktmpdir do |dir|
      sig_dir = File.join(dir, 'sig')
      FileUtils.mkdir_p(sig_dir)

      # core_root: nil — no core types
      loader = RBS::EnvironmentLoader.new(core_root: nil)
      loader.add(path: Pathname(sig_dir))
      env = RBS::Environment.from_loader(loader).resolve_type_names
      builder = RBS::DefinitionBuilder.new(env: env)

      expect { builder.build_instance(RBS::TypeName.parse('::Numeric')) }
        .to raise_error(RuntimeError, /Unknown name/)
    end
  end
end
