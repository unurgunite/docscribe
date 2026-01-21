# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'

RSpec.describe 'docscribe init' do
  let(:exe) { File.expand_path('../exe/docscribe', __dir__) }

  it 'creates docscribe.yml by default' do
    Dir.mktmpdir do |dir|
      _out, _err, status = Open3.capture3(RbConfig.ruby, exe, 'init', chdir: dir)
      expect(status.success?).to be(true)
      expect(File).to exist(File.join(dir, 'docscribe.yml'))
    end
  end

  it "doesn't overwrite an existing file without --force" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'docscribe.yml')
      File.write(path, "foo: bar\n")

      _out, _err, status = Open3.capture3(RbConfig.ruby, exe, 'init', chdir: dir)
      expect(status.success?).to be(false)
      expect(File.read(path)).to eq("foo: bar\n")
    end
  end

  it 'overwrites with --force' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'docscribe.yml')
      File.write(path, "foo: bar\n")

      _out, _err, status = Open3.capture3(RbConfig.ruby, exe, 'init', '--force', chdir: dir)
      expect(status.success?).to be(true)
      expect(File.read(path)).to include('Docscribe configuration file')
    end
  end
end
