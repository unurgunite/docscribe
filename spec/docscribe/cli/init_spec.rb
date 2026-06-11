# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  describe 'default behavior' do
    subject(:result) { Open3.capture3(RbConfig.ruby, exe, 'init', chdir: dir) }

    it 'exits successfully' do
      expect(result[2].success?).to be(true)
    end

    it 'creates docscribe.yml file' do
      result
      expect(File).to exist(File.join(dir, 'docscribe.yml'))
    end
  end

  describe "doesn't overwrite" do
    subject(:result) { Open3.capture3(RbConfig.ruby, exe, 'init', chdir: dir) }

    before { File.write(File.join(dir, 'docscribe.yml'), "foo: bar\n") }

    it 'exits with failure' do
      expect(result[2].success?).to be(false)
    end

    it 'preserves content' do
      result
      expect(File.read(File.join(dir, 'docscribe.yml'))).to eq("foo: bar\n")
    end
  end

  describe 'overwrites with --force' do
    subject(:result) { Open3.capture3(RbConfig.ruby, exe, 'init', '--force', chdir: dir) }

    before { File.write(File.join(dir, 'docscribe.yml'), "foo: bar\n") }

    it 'exits successfully' do
      expect(result[2].success?).to be(true)
    end

    it 'writes new content' do
      result
      expect(File.read(File.join(dir, 'docscribe.yml'))).to include('Docscribe configuration file')
    end
  end
end
