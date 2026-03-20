# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rbconfig'

RSpec.describe 'CLI -a' do
  let(:exe) { File.expand_path('../exe/docscribe', __dir__) }

  it 'applies safe doc updates in place' do
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
        '-a',
        'abc.rb',
        chdir: dir
      )

      expect(status.success?).to be(true), stderr

      out = File.read(path)
      expect(out).to include('# @todo docs (keep this line!)')
      expect(out).to include('# @return [String] already documented')
      expect(out).to include(param_tag('x', 'Object'))
      expect(out).to include(param_tag('y', 'Integer'))
    end
  end
end
