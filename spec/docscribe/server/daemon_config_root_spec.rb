# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'docscribe/server'

RSpec.describe Docscribe::Server::Daemon do
  describe 'config-root anchored signature hashing' do
    around do |ex|
      Dir.mktmpdir do |project|
        Dir.mktmpdir do |elsewhere|
          @project = project
          @elsewhere = elsewhere
          Dir.chdir(elsewhere, &ex)
        end
      end
    end

    let(:project) { @project } # rubocop:disable RSpec/InstanceVariable
    let(:elsewhere) { @elsewhere } # rubocop:disable RSpec/InstanceVariable -- around owns the temp dir
    let(:config_path) { File.join(project, 'docscribe.yml') }
    let(:sig_config) { Docscribe::Config.new(config_path: config_path, 'rbs' => { 'sig_dirs' => ['sig'] }) }
    let(:daemon) { described_class.new(socket_path: File.join(elsewhere, 'x.sock'), config_path: config_path) }

    before do
      FileUtils.mkdir_p(File.join(project, 'sig'))
      File.write(File.join(project, 'sig', 'demo.rbs'), "class Demo\n  def foo: () -> Integer\nend\n")
      File.write(config_path, "rbs:\n  enabled: true\n  sig_dirs: [\"sig\"]\n")
      daemon.send(:load_dependencies)
    end

    it 'hashes sig files from the config root, not Dir.pwd' do
      hash_from_elsewhere = daemon.send(:sig_hash_for, sig_config)

      Dir.chdir(project) do
        expect(daemon.send(:sig_hash_for, sig_config)).to eq(hash_from_elsewhere)
      end
    end

    it 'changes the hash when a sig file under the config root changes' do
      before_hash = daemon.send(:sig_hash_for, sig_config)
      sleep 0.05
      File.write(File.join(project, 'sig', 'demo.rbs'), "class Demo\n  def foo: () -> String\nend\n")

      expect(daemon.send(:sig_hash_for, sig_config)).not_to eq(before_hash)
    end
  end

  describe '.socket_path / .env_hash config-root anchoring' do
    around { |ex| Dir.mktmpdir { |project| @project = project and ex.run } }

    let(:project) { @project } # rubocop:disable RSpec/InstanceVariable
    let(:config_path) { File.join(project, 'docscribe.yml') }

    before do
      FileUtils.mkdir_p(File.join(project, 'sig'))
      File.write(File.join(project, 'sig', 'demo.rbs'), "class Demo\nend\n")
      File.write(config_path, "rbs:\n  enabled: true\n")
    end

    it 'derives the same socket path from a subdirectory and from the project root' do
      sub_dir = File.join(project, 'sub')
      FileUtils.mkdir_p(sub_dir)

      from_sub = Dir.chdir(sub_dir) { Docscribe::Server.socket_path(config_path) }
      from_root = Dir.chdir(project) { Docscribe::Server.socket_path(config_path) }

      expect(from_sub).to eq(from_root)
    end

    it 'includes sig files under the config root' do
      before_hash = Docscribe::Server.env_hash(project)
      File.write(File.join(project, 'sig', 'other.rbs'), "class Other\nend\n")

      expect(Docscribe::Server.env_hash(project)).not_to eq(before_hash)
    end
  end
end
