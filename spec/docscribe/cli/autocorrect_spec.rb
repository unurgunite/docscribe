# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, 'abc.rb') }

  let(:code) do
    <<~RUBY
      class A
        # @todo docs (keep this line!)
        # @return [String] already documented
        def foo(x, y: 1)
          "ok"
        end
      end
    RUBY
  end

  before { File.write(path, code) }

  describe 'result' do
    subject(:result) { Open3.capture3(RbConfig.ruby, exe, '-a', 'abc.rb', chdir: dir) }

    after { FileUtils.rm_rf(dir) }

    it 'exits successfully' do
      _stdout, stderr, status = result
      expect(status.success?).to be(true), stderr
    end

    it 'keeps @todo docs' do
      result
      expect(File.read(path)).to include('# @todo docs (keep this line!)')
    end

    it 'keeps existing @return' do
      result
      expect(File.read(path)).to include('# @return [String] already documented')
    end

    it 'adds @param for x' do
      result
      expect(File.read(path)).to include(param_tag('x', 'Object'))
    end

    it 'adds @param for y' do
      result
      expect(File.read(path)).to include(param_tag('y', 'Integer'))
    end
  end
end
