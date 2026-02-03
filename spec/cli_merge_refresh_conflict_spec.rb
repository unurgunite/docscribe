# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'

RSpec.describe 'CLI --refresh/--merge conflict' do
  let(:exe) { File.expand_path('../exe/docscribe', __dir__) }

  it 'errors and exits 1 when --refresh and --merge are both provided' do
    Dir.mktmpdir do |dir|
      code = "class A; def x; 1; end; end\n"

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, exe,
        '--stdin',
        '--merge',
        '--refresh',
        stdin_data: code,
        chdir: dir
      )

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq('')
      expect(stderr).to include('cannot combine --refresh and --merge')
    end
  end
end
