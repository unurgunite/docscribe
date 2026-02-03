# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'

RSpec.describe 'CLI --verbose' do
  let(:exe) { File.expand_path('../exe/docscribe', __dir__) }

  it 'prints per-file actions in --dry mode' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a_ok.rb'), <<~RUBY)
        class A
          # already documented
          def x; 1; end
        end
      RUBY

      File.write(File.join(dir, 'b_fail.rb'), <<~RUBY)
        class B
          def y; 1; end
        end
      RUBY

      stdout, _stderr, status = Open3.capture3(
        RbConfig.ruby, exe, '--dry', '--verbose', dir,
        chdir: dir
      )

      expect(status.success?).to be(false)
      expect(stdout).to include('OK a_ok.rb')
      expect(stdout).to include('FAIL b_fail.rb')
    end
  end
end
