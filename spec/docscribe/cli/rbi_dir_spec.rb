# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI do
  before { skip_unless_sorbet_bridge_available! }

  describe '--rbi-dir' do
    subject(:result) do
      Open3.capture3(RbConfig.ruby, exe, '--stdin', '--rbi-dir', 'sorbet/rbi', stdin_data: code, chdir: dir)
    end

    let(:dir) { Dir.mktmpdir }
    let(:code) do
      <<~RUBY
        class Demo
          def foo(verbose:)
            "a"
          end
        end
      RUBY
    end

    after { FileUtils.rm_rf(dir) }

    before do
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
    end

    it 'exits successfully' do
      _, stderr, status = result
      expect(status.success?).to be(true), stderr
    end

    it 'uses RBI @return' do
      expect(result[0]).to include('# @return [Integer]')
    end

    it 'uses RBI @param' do
      expect(result[0]).to include(param_tag('verbose', 'Boolean'))
    end

    it 'ignores Ruby @return override' do
      expect(result[0]).not_to include('# @return [String]')
    end
  end

  describe '--sorbet with inline sigs' do
    subject(:result) do
      Open3.capture3(RbConfig.ruby, exe, '--stdin', '--sorbet', stdin_data: code, chdir: dir)
    end

    let(:dir) { Dir.mktmpdir }
    let(:code) do
      <<~RUBY
        class Demo
          extend T::Sig

          sig { params(verbose: T::Boolean).returns(Integer) }
          def foo(verbose:)
            "a"
          end
        end
      RUBY
    end

    after { FileUtils.rm_rf(dir) }

    it 'exits successfully' do
      _, stderr, status = result
      expect(status.success?).to be(true), stderr
    end

    it 'uses sig @return' do
      expect(result[0]).to include('# @return [Integer]')
    end

    it 'uses sig @param' do
      expect(result[0]).to include(param_tag('verbose', 'Boolean'))
    end

    it 'ignores Ruby @return override' do
      expect(result[0]).not_to include('# @return [String]')
    end
  end
end
