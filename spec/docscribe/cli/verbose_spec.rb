# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI do
  let(:dir) { Dir.mktmpdir }
  let(:stdout) do
    File.write(File.join(dir, 'a_ok.rb'), <<~RUBY)
      class A
        # @param [Object] x Param documentation.
        # @return [Integer]
        def x(x); 1; end
      end
    RUBY

    File.write(File.join(dir, 'b_fail.rb'), <<~RUBY)
      class B
        def y; 1; end
      end
    RUBY

    out, = Open3.capture3(RbConfig.ruby, exe, '--verbose', dir, chdir: dir)
    out
  end

  after { FileUtils.rm_rf(dir) }

  it 'exits with failure status' do
    Dir.mktmpdir do |d|
      File.write(File.join(d, 'a_ok.rb'), '')
      File.write(File.join(d, 'b_fail.rb'), '')
      expect(Open3.capture3(RbConfig.ruby, exe, '--verbose', d, chdir: d)[2].success?).to be(false)
    end
  end

  it { expect(stdout).to include('OK a_ok.rb') }

  it { expect(stdout).to include('FAIL b_fail.rb') }
end
