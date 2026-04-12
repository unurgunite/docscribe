# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

RSpec.describe 'CLI Sorbet support' do
  it 'loads Sorbet RBI signatures from --rbi-dir and uses them for @param/@return' do
    skip_unless_sorbet_bridge_available!

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'sorbet/rbi'))

      File.write(File.join(dir, 'sorbet/rbi', 'demo.rbi'), <<~RBI)
        # typed: strict
        class Demo
          extend T::Sig

          sig { params(verbose: T::Boolean).returns(Integer) }
          def foo(verbose:)
          end
        end
      RBI

      code = <<~RUBY
        class Demo
          def foo(verbose:)
            "a"
          end
        end
      RUBY

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        exe,
        '--stdin',
        '--rbi-dir',
        'sorbet/rbi',
        stdin_data: code,
        chdir: dir
      )

      expect(status.success?).to be(true), stderr
      expect(stdout).to include('# +Demo#foo+ -> Integer')
      expect(stdout).to include('# @return [Integer]')
      expect(stdout).to include(param_tag('verbose', 'Boolean'))
      expect(stdout).not_to include('# @return [String]')
    end
  end

  it 'uses inline sigs from stdin when --sorbet is enabled' do
    skip_unless_sorbet_bridge_available!

    code = <<~RUBY
      class Demo
        extend T::Sig

        sig { params(verbose: T::Boolean).returns(Integer) }
        def foo(verbose:)
          "a"
        end
      end
    RUBY

    Dir.mktmpdir do |dir|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        exe,
        '--stdin',
        '--sorbet',
        stdin_data: code,
        chdir: dir
      )

      expect(status.success?).to be(true), stderr
      expect(stdout).to include('# +Demo#foo+ -> Integer')
      expect(stdout).to include('# @return [Integer]')
      expect(stdout).to include(param_tag('verbose', 'Boolean'))
      expect(stdout).not_to include('# @return [String]')
    end
  end
end
