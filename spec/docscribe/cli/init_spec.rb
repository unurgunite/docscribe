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

  describe 'pre-commit hook' do
    subject(:result) { Open3.capture3(RbConfig.ruby, exe, 'init', '--pre-commit', chdir: dir) }

    context 'when .git/hooks does not exist' do
      it 'exits with failure' do
        expect(result[2].success?).to be(false)
      end

      it 'prints warning' do
        expect(result[1]).to include('No .git/hooks directory found')
      end
    end

    context 'when .git/hooks exists' do
      before do
        FileUtils.mkdir_p(File.join(dir, '.git', 'hooks'))
      end

      it 'creates pre-commit hook file' do
        result
        hook_path = File.join(dir, '.git', 'hooks', 'pre-commit')
        expect(File).to exist(hook_path)
      end

      it 'makes hook executable' do
        result
        hook_path = File.join(dir, '.git', 'hooks', 'pre-commit')
        expect(File.stat(hook_path).mode & 0o777).to eq(0o755)
      end

      it 'contains docscribe check command' do
        result
        hook_path = File.join(dir, '.git', 'hooks', 'pre-commit')
        expect(File.read(hook_path)).to include('bundle exec docscribe check')
      end

      it 'exits successfully' do
        expect(result[2].success?).to be(true)
      end
    end

    context 'when hook already exists' do
      before do
        FileUtils.mkdir_p(File.join(dir, '.git', 'hooks'))
        File.write(File.join(dir, '.git', 'hooks', 'pre-commit'), '#!/bin/sh')
      end

      it 'exits with failure' do
        expect(result[2].success?).to be(false)
      end

      it 'prints warning about existing hook' do
        expect(result[1]).to include('already exists')
      end
    end

    context 'when hook exists with --force' do
      subject(:result) { Open3.capture3(RbConfig.ruby, exe, 'init', '--pre-commit', '--force', chdir: dir) }

      before do
        FileUtils.mkdir_p(File.join(dir, '.git', 'hooks'))
        File.write(File.join(dir, '.git', 'hooks', 'pre-commit'), '#!/bin/sh')
      end

      it 'overwrites the existing hook' do
        result
        hook_content = File.read(File.join(dir, '.git', 'hooks', 'pre-commit'))
        expect(hook_content).to include('bundle exec docscribe check')
      end

      it 'exits successfully' do
        expect(result[2].success?).to be(true)
      end
    end
  end
end
