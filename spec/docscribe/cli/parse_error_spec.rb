# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

RSpec.describe 'CLI parse error handling' do
  it 'continues when one file has a syntax error and exits non-zero' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a_bad.rb'), <<~RUBY)
        class A
          def x
            1 + )
          end
        end
      RUBY

      File.write(File.join(dir, 'b_good.rb'), <<~RUBY)
        class B
          # @return [Integer]
          def y; 1; end
        end
      RUBY

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, exe, dir,
        chdir: dir
      )

      expect(status.success?).to be(false)

      progress = stdout.lines.first&.strip
      expect(progress).to eq('E.')

      expect(stderr).to include('Error processing:')
      expect(stderr).to include('a_bad.rb')
    end
  end
end
