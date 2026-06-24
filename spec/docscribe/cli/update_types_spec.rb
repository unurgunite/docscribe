# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'
require 'docscribe/cli'
require 'docscribe/cli/update_types'

DEFAULT_OPTS = Docscribe::CLI::Options::DEFAULT.dup

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

    describe '.run_first_pass' do
      before do
        opts = DEFAULT_OPTS.merge(mode: :write, strategy: :aggressive, rbs_collection: true, no_boilerplate: true, keep_descriptions: true, rbs: true)
        allow(Docscribe::CLI::Options).to receive(:parse!).and_return(opts)
        allow(Docscribe::CLI::Run).to receive(:run)
      end

      it 'calls Options.parse! with aggressive flags' do
        described_class.send(:run_first_pass, 'lib')
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('-AkB'))
      end

      it 'calls Options.parse! with rbs-collection flag' do
        described_class.send(:run_first_pass, 'lib')
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs-collection'))
      end

      it 'calls Run.run with write mode and aggressive strategy' do
        described_class.send(:run_first_pass, 'lib')
        expect(Docscribe::CLI::Run).to have_received(:run).with(
          options: hash_including(mode: :write, strategy: :aggressive),
          argv: ['lib']
        )
      end
    end

    describe '.run_second_pass' do
      before do
        opts = DEFAULT_OPTS.merge(mode: :write, strategy: :safe, rbs_collection: true, no_boilerplate: true, rbs: true)
        allow(Docscribe::CLI::Options).to receive(:parse!).and_return(opts)
        allow(Docscribe::CLI::Run).to receive(:run)
      end

      it 'calls Options.parse! with safe flags' do
        described_class.send(:run_second_pass, 'lib')
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('-aB'))
      end

      it 'calls Options.parse! with rbs-collection flag' do
        described_class.send(:run_second_pass, 'lib')
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs-collection'))
      end

      it 'calls Run.run with write mode and safe strategy' do
        described_class.send(:run_second_pass, 'lib')
        expect(Docscribe::CLI::Run).to have_received(:run).with(
          options: hash_including(mode: :write, strategy: :safe),
          argv: ['lib']
        )
      end
    end
  end

  describe '.run' do
    it 'exits early if pass 1 fails' do
      allow(described_class).to receive(:run_first_pass).with('.').and_return(2)
      expect(described_class.run([])).to eq(2)
    end

    it 'does not run pass 2 when pass 1 fails' do
      allow(described_class).to receive(:run_first_pass).with('.').and_return(2)
      allow(described_class).to receive(:run_second_pass)
      described_class.run([])
      expect(described_class).not_to have_received(:run_second_pass)
    end

    it 'runs both passes and returns pass 2 exit code' do
      allow(described_class).to receive(:run_first_pass).with('.').and_return(0)
      allow(described_class).to receive(:run_second_pass).with('.').and_return(1)
      expect(described_class.run([])).to eq(1)
    end

    it 'returns 0 when both passes succeed' do
      allow(described_class).to receive(:run_first_pass).with('.').and_return(0)
      allow(described_class).to receive(:run_second_pass).with('.').and_return(0)
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
