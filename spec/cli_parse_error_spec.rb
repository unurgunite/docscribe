# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

RSpec.describe 'CLI parse error handling' do
  let(:exe) { File.expand_path('../exe/docscribe', __dir__) }

  it 'continues when one file has a syntax error and exits non-zero' do
    Dir.mktmpdir do |dir|
      # Unambiguously invalid Ruby (should raise in parser + prism)
      File.write(File.join(dir, 'a_bad.rb'), <<~RUBY)
        class A
          def x
            1 + )
          end
        end
      RUBY

      # This file should be processed and be OK under --dry because it already has a comment
      File.write(File.join(dir, 'b_good.rb'), <<~RUBY)
        class B
          # already documented
          def y; 1; end
        end
      RUBY

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, exe, '--dry', dir,
        chdir: dir
      )

      expect(status.success?).to be(false)

      # Progress markers are printed on the first line (e.g. "E.")
      progress = stdout.lines.first&.strip
      expect(progress).to eq('E.')

      # Error summary should go to stderr
      expect(stderr).to include('Error processing:')
      expect(stderr).to include('a_bad.rb')
    end
  end
end
