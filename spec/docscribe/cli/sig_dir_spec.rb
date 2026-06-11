# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI do
  before { skip_unless_rbs_available! }

  describe 'RBS signatures from --sig-dir' do
    subject(:result) do
      Open3.capture3(RbConfig.ruby, exe, '--stdin', '--sig-dir', 'sig', stdin_data: code, chdir: dir)
    end

    let(:dir) { Dir.mktmpdir }
    let(:code) do
      <<~RUBY
        class D
          def x(verbose:)
            "a"
          end
        end
      RUBY
    end

    after { FileUtils.rm_rf(dir) }

    before do
      FileUtils.mkdir_p(File.join(dir, 'sig'))
      File.write(File.join(dir, 'sig', 'd.rbs'), <<~RBS)
        class D
          def x: (verbose: bool) -> Integer
        end
      RBS
    end

    it 'exits successfully' do
      _, stderr, status = result
      expect(status.success?).to be(true), stderr
    end

    it 'uses RBS @return' do
      expect(result[0]).to include('# @return [Integer]')
    end

    it 'uses RBS @param' do
      expect(result[0]).to include(param_tag('verbose', 'Boolean'))
    end
  end
end
