# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI do
  subject(:result) { Open3.capture3(RbConfig.ruby, exe, dir, chdir: dir) }

  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  before do
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
  end

  it 'exits non-zero' do
    expect(result[2].success?).to be(false)
  end

  it 'shows progress with E' do
    expect(result[1]).to include('E')
  end

  it 'reports error processing' do
    expect(result[1]).to include('Error processing:')
  end

  it 'reports bad file' do
    expect(result[1]).to include('a_bad.rb')
  end
end
