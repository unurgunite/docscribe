# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

RSpec.describe 'CLI --sig-dir' do
  it 'loads RBS signatures from --sig-dir and uses them for @param/@return (when available)' do
    begin
      require 'rbs'
    rescue LoadError
      skip 'RBS not available'
    end

    exe = File.expand_path('../exe/docscribe', __dir__)

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'sig'))

      # RBS says x returns Integer and verbose is bool.
      File.write(File.join(dir, 'sig', 'd.rbs'), <<~RBS)
        class D
          def x: (verbose: bool) -> Integer
        end
      RBS

      # Ruby returns a String, so inference would produce String unless RBS is used.
      code = <<~RUBY
        class D
          def x(verbose:)
            "a"
          end
        end
      RUBY

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, exe,
        '--stdin',
        '--sig-dir', 'sig', # implies --rbs in your CLI
        stdin_data: code,
        chdir: dir
      )

      expect(status.success?).to be(true), stderr

      expect(stdout).to include('# +D#x+ -> Integer')
      expect(stdout).to include('# @return [Integer]')
      expect(stdout).to include('# @param [Boolean] verbose')
    end
  end
end
