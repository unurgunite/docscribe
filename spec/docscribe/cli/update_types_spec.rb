# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI::UpdateTypes do
  describe 'helper methods' do
    describe '.parse_options' do
      it 'defaults dir to .' do
        opts = described_class.send(:parse_options, [])
        expect(opts[:dir]).to eq('.')
      end

      it 'accepts a directory argument' do
        Dir.mktmpdir do |dir|
          opts = described_class.send(:parse_options, [dir])
          expect(opts[:dir]).to eq(dir)
        end
      end
    end

    describe '.run_pass_1' do
      it 'calls Options.parse! and Run.run with correct flags' do
        expect(Docscribe::CLI::Options).to receive(:parse!).with(['-AkB', '--rbs-collection', 'lib']).and_call_original
        expect(Docscribe::CLI::Run).to receive(:run).with(options: hash_including(mode: :write, strategy: :aggressive), argv: ['lib'])
        described_class.send(:run_pass_1, 'lib')
      end
    end

    describe '.run_pass_2' do
      it 'calls Options.parse! and Run.run with correct flags' do
        expect(Docscribe::CLI::Options).to receive(:parse!).with(['-aB', '--rbs-collection', 'lib']).and_call_original
        expect(Docscribe::CLI::Run).to receive(:run).with(options: hash_including(mode: :write, strategy: :safe), argv: ['lib'])
        described_class.send(:run_pass_2, 'lib')
      end
    end
  end

  describe '.run' do
    it 'exits early if pass 1 fails' do
      expect(described_class).to receive(:run_pass_1).with('.').and_return(2)
      expect(described_class).not_to receive(:run_pass_2)
      expect(described_class.run([])).to eq(2)
    end

    it 'runs both passes and returns pass 2 exit code' do
      expect(described_class).to receive(:run_pass_1).with('.').and_return(0)
      expect(described_class).to receive(:run_pass_2).with('.').and_return(1)
      expect(described_class.run([])).to eq(1)
    end

    it 'returns 0 when both passes succeed' do
      expect(described_class).to receive(:run_pass_1).with('.').and_return(0)
      expect(described_class).to receive(:run_pass_2).with('.').and_return(0)
      expect(described_class.run([])).to eq(0)
    end
  end

  describe 'CLI integration' do
    subject(:result) { Open3.capture3('ruby', exe, 'update_types', *args) }

    let(:args) { [] }

    describe '--help' do
      let(:args) { ['--help'] }

      it 'shows usage' do
        expect(result[0]).to include('Usage:')
      end

      it 'exits 0' do
        expect(result[2].exitstatus).to eq(0)
      end
    end
  end
end
