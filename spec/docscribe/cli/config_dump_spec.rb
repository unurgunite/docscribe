# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'docscribe/cli/config_dump'

RSpec.describe Docscribe::CLI::ConfigDump do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  describe '.run' do
    it 'returns 0 with --help' do
      expect(described_class.run(%w[--help])).to be(0)
    end

    it 'prints YAML emit key' do
      File.write(File.join(tmpdir, 'docscribe.yml'), "emit:\n  header: true\n")
      stdout = capture_stdout { described_class.run(%W[--config #{File.join(tmpdir, 'docscribe.yml')}]) }
      expect(stdout).to include('emit:')
    end

    it 'prints YAML header key' do
      File.write(File.join(tmpdir, 'docscribe.yml'), "emit:\n  header: true\n")
      stdout = capture_stdout { described_class.run(%W[--config #{File.join(tmpdir, 'docscribe.yml')}]) }
      expect(stdout).to include('header:')
    end

    it 'prints config with CLI overrides' do
      File.write(File.join(tmpdir, 'docscribe.yml'), "emit:\n  header: true\n")
      stdout = capture_stdout { described_class.run(%W[--config #{File.join(tmpdir, 'docscribe.yml')} lib]) }
      expect(stdout).to include('emit:')
    end

    context 'with --only-changed' do
      it 'shows only the keys the config overrides' do
        path = File.join(tmpdir, 'docscribe.yml')
        File.write(path, "emit:\n  header: true\n")
        stdout = capture_stdout { described_class.run(%W[--config #{path} --only-changed]) }
        expect(stdout).to include('header: true')
        expect(stdout).not_to include('param_tags')
      end

      it 'prints an empty document when the config changes nothing' do
        path = File.join(tmpdir, 'docscribe.yml')
        File.write(path, "emit:\n  header: false\n")
        stdout = capture_stdout { described_class.run(%W[--config #{path} --only-changed]) }
        expect(stdout.strip).to eq('--- {}')
      end
    end

    context 'with --format json' do
      it 'emits valid JSON' do
        path = File.join(tmpdir, 'docscribe.yml')
        File.write(path, "emit:\n  header: true\n")
        stdout = capture_stdout { described_class.run(%W[--config #{path} --only-changed --format json]) }
        expect(JSON.parse(stdout)).to eq({ 'emit' => { 'header' => true } })
      end
    end

    context 'with --format text' do
      it 'renders flattened key=value lines' do
        path = File.join(tmpdir, 'docscribe.yml')
        File.write(path, "emit:\n  header: true\n")
        stdout = capture_stdout { described_class.run(%W[--config #{path} --only-changed --format text]) }
        expect(stdout).to include('emit.header=true')
      end
    end
  end
end
