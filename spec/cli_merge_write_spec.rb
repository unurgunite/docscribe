# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'

RSpec.describe 'CLI --merge --write' do
  let(:exe) { File.expand_path('../exe/docscribe', __dir__) }

  it 'merges missing tags into an existing doc-like block' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'abc.rb')

      File.write(path, <<~RUBY)
        class A
          # @todo docs (keep this line!)
          # @return [String] already documented
          def foo(x, y: 1)
            "ok"
          end
        end
      RUBY

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, exe,
        '--write',
        '--merge',
        'abc.rb',
        chdir: dir
      )

      expect(status.success?).to be(true), stderr

      out = File.read(path)
      expect(out).to include('# @todo docs (keep this line!)')
      expect(out).to include('# @return [String] already documented')
      expect(out).to include('# @param [Object] x')
      expect(out).to include('# @param [Integer] y')
    end
  end
end
