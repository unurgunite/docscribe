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
  end
end
