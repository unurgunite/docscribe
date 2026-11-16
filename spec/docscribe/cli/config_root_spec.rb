# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'

RSpec.describe Docscribe::CLI do
  let(:lock_warning) { /rbs_collection\.lock\.yaml found but --rbs-collection not set/ }

  def run_cli(dir, *args)
    Open3.capture3('ruby', exe, *args, chdir: dir)
  end

  def write_project(root, **config)
    FileUtils.mkdir_p(File.join(root, 'lib'))
    FileUtils.mkdir_p(File.join(root, 'sub'))
    File.write(File.join(root, 'docscribe.yml'), config.to_yaml)
    File.write(File.join(root, 'lib', 'demo.rb'), "module Demo\n  class Thin\n    def value\n      1\n    end\n  end\nend\n")
    FileUtils.cp(File.join(root, 'lib', 'demo.rb'), File.join(root, 'sub', 'demo.rb'))
    File.write(File.join(root, 'rbs_collection.lock.yaml'), "---\npath: \".gem_rbs_collection\"\ngems: []\n")
    FileUtils.mkdir_p(File.join(root, '.gem_rbs_collection'))
  end

  describe 'missing-collection warning' do
    around do |ex|
      Dir.mktmpdir { |dir| @root = dir and ex.run }
    end

    let(:root) { @root } # rubocop:disable RSpec/InstanceVariable -- around hooks own the temp dir

    before { write_project(root, 'rbs' => { 'enabled' => true, 'sig_dirs' => ['sig'] }) }

    it 'fires on a plain run with no override flags' do
      _, stderr, = run_cli(root, '--', 'lib/demo.rb')
      expect(stderr).to match(lock_warning)
    end

    it 'fires from a subdirectory via -C' do
      _, stderr, = run_cli(File.join(root, 'sub'), '-C', '../docscribe.yml', '--', 'demo.rb')
      expect(stderr).to match(lock_warning)
    end

    it 'fires when unrelated overrides are present' do
      _, stderr, = run_cli(root, '--rbs', '--', 'lib/demo.rb')
      expect(stderr).to match(lock_warning)
    end

    it 'stays silent when --rbs-collection was passed' do
      _, stderr, = run_cli(root, '--rbs-collection', '--', 'lib/demo.rb')
      expect(stderr).not_to match(lock_warning)
    end

    it 'stays silent when rbs.warn_missing_collection is false' do
      write_project(root, 'rbs' => { 'enabled' => true, 'warn_missing_collection' => false })
      _, stderr, = run_cli(root, '--', 'lib/demo.rb')
      expect(stderr).not_to match(lock_warning)
    end
  end

  describe 'sig_dirs resolution' do
    around do |ex|
      skip_unless_rbs_available!
      Dir.mktmpdir { |dir| @root = dir and ex.run }
    end

    let(:root) { @root } # rubocop:disable RSpec/InstanceVariable -- around hooks own the temp dir

    before do
      write_project(root, 'rbs' => { 'enabled' => true, 'sig_dirs' => ['sig'] })
      FileUtils.mkdir_p(File.join(root, 'sig'))
      File.write(File.join(root, 'sig', 'demo.rbs'), <<~RBS)
        module Demo
          class Thin
            def value: () -> String
          end
        end
      RBS
    end

    it 'produces the same output from the project root and from a subdirectory' do
      root_out, = run_cli(root, '--', 'lib/demo.rb')
      sub_out, = run_cli(File.join(root, 'sub'), '-C', '../docscribe.yml', '--', 'demo.rb')

      expect(root_out[/Docscribe: (?:FAILED|OK) \(.*\)/]).to eq('Docscribe: FAILED (1 need updates, 0 errors, 0 ok)')
      expect(sub_out[/Docscribe: (?:FAILED|OK) \(.*\)/]).to eq('Docscribe: FAILED (1 need updates, 0 errors, 0 ok)')
    end
  end
end
