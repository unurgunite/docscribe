# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'pathname'

RSpec.describe Docscribe::Config do
  describe '#config_root' do
    it 'falls back to Dir.pwd when config_path is nil' do
      expect(described_class.new.config_root).to eq(File.expand_path(Dir.pwd))
    end

    it 'uses the directory holding a relative config_path' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write('docscribe.yml', "rbs:\n  enabled: true\n")
          expect(described_class.load.config_root).to eq(File.realpath(dir))
        end
      end
    end

    it 'uses the directory holding an absolute config_path' do
      Dir.mktmpdir do |dir|
        conf_path = File.join(dir, 'custom.yml')
        File.write(conf_path, "rbs:\n  enabled: true\n")
        expect(described_class.new(config_path: conf_path).config_root).to eq(File.expand_path(dir))
      end
    end

    it 'resolves a nested relative config_path against Dir.pwd' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'configs'))
        File.write(File.join(dir, 'configs', 'docscribe.yml'), "rbs:\n  enabled: true\n")
        Dir.chdir(dir) do
          expect(described_class.new(config_path: 'configs/docscribe.yml').config_root)
            .to eq(File.join(File.realpath(dir), 'configs'))
        end
      end
    end

    it 'raises a clear error when the config directory does not exist' do
      conf = described_class.new(config_path: '/nonexistent-dir/docscribe.yml')
      expect { conf.config_root }.to raise_error(Docscribe::Error, /config directory not found/)
    end
  end

  describe '#resolve_path' do
    it 'returns absolute paths untouched' do
      conf = described_class.new(config_path: '/project/docscribe.yml')
      expect(conf.resolve_path('/elsewhere/sig')).to eq('/elsewhere/sig')
    end

    it 'expands a relative path from the config root, not Dir.pwd' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'docscribe.yml'), "rbs:\n  enabled: true\n")
        Dir.mktmpdir do |other|
          Dir.chdir(other) do
            conf = described_class.new(config_path: File.join(dir, 'docscribe.yml'))
            expect(conf.resolve_path('sig')).to eq(File.expand_path(File.join(dir, 'sig')))
          end
        end
      end
    end

    it 'expands from Dir.pwd when config_path is nil' do
      expect(described_class.new.resolve_path('sig')).to eq(File.expand_path(File.join(Dir.pwd, 'sig')))
    end
  end

  describe 'config-relative path resolution' do
    around do |ex|
      Dir.mktmpdir { |t| Dir.chdir(t, &ex) }
    end

    let(:project) { Dir.mktmpdir }
    let(:config_path) { File.join(project, 'docscribe.yml') }

    before { File.write(config_path, "rbs:\n  enabled: true\n") }

    after { FileUtils.rm_rf(project) }

    it 'resolves rbs.sig_dirs from the config directory' do
      conf = described_class.new(config_path: config_path, 'rbs' => { 'enabled' => true, 'sig_dirs' => ['sig'] })
      expect(conf.instance_eval { rbs_sig_dirs }).to eq([File.join(project, 'sig')])
    end

    it 'keeps absolute rbs.sig_dirs untouched' do
      conf = described_class.new(config_path: config_path, 'rbs' => { 'sig_dirs' => ['/abs/sig'] })
      expect(conf.instance_eval { rbs_sig_dirs }).to eq(['/abs/sig'])
    end

    it 'resolves rbs.collection_dirs from the config directory' do
      conf = described_class.new(config_path: config_path, 'rbs' => { 'collection_dirs' => ['.gem_rbs_collection'] })
      expect(conf.instance_eval { rbs_collection_dirs }).to eq([File.join(project, '.gem_rbs_collection')])
    end

    it 'resolves sorbet.rbi_dirs from the config directory' do
      conf = described_class.new(config_path: config_path, 'sorbet' => { 'rbi_dirs' => ['rbi'] })
      expect(conf.sorbet_rbi_dirs).to eq([File.join(project, 'rbi')])
    end

    it 'discovers the RBS collection lock file next to the config file' do
      FileUtils.mkdir_p(File.join(project, '.gem_rbs_collection'))
      File.write(File.join(project, 'rbs_collection.lock.yaml'), "---\npath: \".gem_rbs_collection\"\ngems: []\n")

      conf = described_class.new(config_path: config_path, 'rbs' => { 'collection' => true })
      expect(conf.instance_eval { rbs_collection_dirs }).to eq([File.join(project, '.gem_rbs_collection')])
    end

    it 'loads plugins.require relative to the config directory' do
      File.write(File.join(project, 'my_plugin.rb'), "Docscribe::Plugin::Registry.register(proc { |value| value })\n")
      conf = described_class.new(config_path: config_path, 'plugins' => { 'require' => ['./my_plugin.rb'] })

      begin
        expect { conf.load_plugins! }.not_to output.to_stderr
        expect(Docscribe::Plugin::Registry.tag_plugins.size).to eq(1)
      ensure
        # The registry is global: leaving the plugin registered breaks later examples.
        Docscribe::Plugin::Registry.clear!
      end
    end
  end
end
