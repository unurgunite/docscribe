# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'docscribe/cli/update_types'

RSpec.describe Docscribe::CLI::UpdateTypes do
  describe '.parse_options target handling' do
    context 'when no arguments provided' do
      subject(:parsed_options) { described_class.send(:parse_options, []) }

      it 'defaults dir to .' do
        expect(parsed_options[:dir]).to eq('.')
      end
    end

    context 'when directory argument provided' do
      it 'accepts directory argument' do
        Dir.mktmpdir do |temporary_directory|
          parsed_options = described_class.send(:parse_options, [temporary_directory])
          expect(parsed_options[:dir]).to eq(temporary_directory)
        end
      end
    end

    context 'when file argument provided' do
      it 'accepts file argument as dir (target)' do
        Dir.mktmpdir do |temporary_directory|
          target_file = File.join(temporary_directory, 'a.rb')
          FileUtils.touch(target_file)
          parsed_options = described_class.send(:parse_options, [target_file])
          expect(parsed_options[:dir]).to eq(target_file)
        end
      end
    end

    context 'when --help flag provided' do
      it 'parses --help and exits 0' do
        expect { described_class.send(:parse_options, ['--help']) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(0)
        end
      end
    end
  end

  describe '.run_first_pass RBS flag logic' do
    let(:default_options) { Docscribe::CLI::Options::DEFAULT.dup }
    let(:aggressive_options) do
      default_options.merge(mode: :write, strategy: :aggressive, rbs_collection: true, no_boilerplate: true, keep_descriptions: true, rbs: true)
    end

    before do
      allow(Docscribe::CLI::Options).to receive(:parse!).and_return(aggressive_options)
      allow(Docscribe::CLI::Run).to receive(:run).and_return(0)
    end

    it 'uses --rbs-collection when dir has lock file', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        File.write(File.join(temporary_directory, 'rbs_collection.lock.yaml'), 'x')
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(File.join(temporary_directory, 'rbs_collection.lock.yaml')).and_return(true)
        allow(File).to receive(:exist?).with('rbs_collection.lock.yaml').and_return(false)
        allow(File).to receive(:file?).and_return(false)
        described_class.send(:run_first_pass, temporary_directory)
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs-collection', temporary_directory))
        expect(Docscribe::CLI::Options).not_to have_received(:parse!).with(array_including('--rbs'))
      end
    end

    it 'uses --rbs when no lock file anywhere', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        allow(File).to receive_messages(exist?: false, file?: false)
        described_class.send(:run_first_pass, temporary_directory)
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs', temporary_directory))
        expect(Docscribe::CLI::Options).not_to have_received(:parse!).with(array_including('--rbs-collection'))
      end
    end

    it 'uses --rbs-collection when root has lock even if dir lacks it' do
      Dir.mktmpdir do |temporary_directory|
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(File.join(temporary_directory, 'rbs_collection.lock.yaml')).and_return(false)
        allow(File).to receive(:exist?).with('rbs_collection.lock.yaml').and_return(true)
        allow(File).to receive(:file?).and_return(false)
        described_class.send(:run_first_pass, temporary_directory)
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs-collection'))
      end
    end

    context 'when target is a file with collection lock' do
      it 'uses dirname for flag but passes file to Run', :aggregate_failures do
        Dir.mktmpdir do |temporary_directory|
          target_file = File.join(temporary_directory, 'foo.rb')
          FileUtils.touch(target_file)
          File.write(File.join(temporary_directory, 'rbs_collection.lock.yaml'), 'x')
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:file?).and_call_original
          allow(File).to receive(:file?).with(target_file).and_return(true)
          allow(File).to receive(:file?).with(temporary_directory).and_return(false)
          allow(File).to receive(:exist?).with(File.join(temporary_directory, 'rbs_collection.lock.yaml')).and_return(true)
          allow(File).to receive(:exist?).with('rbs_collection.lock.yaml').and_return(false)
          described_class.send(:run_first_pass, target_file)
          expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including(temporary_directory))
          expect(Docscribe::CLI::Options).not_to have_received(:parse!).with(array_including(target_file))
          expect(Docscribe::CLI::Run).to have_received(:run).with(options: hash_including(strategy: :aggressive), argv: [target_file])
        end
      end
    end

    context 'when file target without collection' do
      it 'uses --rbs with dirname', :aggregate_failures do
        Dir.mktmpdir do |temporary_directory|
          target_file = File.join(temporary_directory, 'foo.rb')
          FileUtils.touch(target_file)
          allow(File).to receive(:exist?).and_return(false)
          allow(File).to receive(:file?).and_call_original
          allow(File).to receive(:file?).with(target_file).and_return(true)
          described_class.send(:run_first_pass, target_file)
          expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs', File.dirname(target_file)))
          expect(Docscribe::CLI::Run).to have_received(:run).with(argv: [target_file], options: anything)
        end
      end
    end

    it 'passes correct strategy aggressive and mode write', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        allow(File).to receive_messages(exist?: false, file?: false)
        described_class.send(:run_first_pass, temporary_directory)
        expect(Docscribe::CLI::Run).to have_received(:run).with(options: hash_including(mode: :write, strategy: :aggressive), argv: [temporary_directory])
      end
    end
  end

  describe '.run_second_pass RBS flag logic' do
    let(:default_options) { Docscribe::CLI::Options::DEFAULT.dup }
    let(:safe_options) do
      default_options.merge(mode: :write, strategy: :safe, rbs_collection: true, no_boilerplate: true, rbs: true)
    end

    before do
      allow(Docscribe::CLI::Options).to receive(:parse!).and_return(safe_options)
      allow(Docscribe::CLI::Run).to receive(:run).and_return(0)
    end

    it 'uses --rbs-collection when present', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        allow(File).to receive_messages(exist?: true, file?: false)
        described_class.send(:run_second_pass, temporary_directory)
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs-collection', temporary_directory))
      end
    end

    it 'uses --rbs when missing', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        allow(File).to receive_messages(exist?: false, file?: false)
        described_class.send(:run_second_pass, temporary_directory)
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including('--rbs'))
        expect(Docscribe::CLI::Options).not_to have_received(:parse!).with(array_including('--rbs-collection'))
      end
    end

    it 'for file target uses dirname for flag', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        target_file = File.join(temporary_directory, 'bar.rb')
        FileUtils.touch(target_file)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:file?).and_call_original
        allow(File).to receive(:file?).with(target_file).and_return(true)
        described_class.send(:run_second_pass, target_file)
        expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including(temporary_directory))
        expect(Docscribe::CLI::Run).to have_received(:run).with(options: hash_including(strategy: :safe), argv: [target_file])
      end
    end

    it 'passes safe strategy', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        allow(File).to receive_messages(exist?: false, file?: false)
        described_class.send(:run_second_pass, temporary_directory)
        expect(Docscribe::CLI::Run).to have_received(:run).with(options: hash_including(strategy: :safe, mode: :write), argv: [temporary_directory])
      end
    end
  end

  describe 'file vs dir integration' do
    let(:first_file_content) { "class A\ndef foo\n1\nend\nend\n" }
    let(:second_file_content) { "class B\ndef bar\n2\nend\nend\n" }

    it 'updates only target file when given file path', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        first_file = File.join(temporary_directory, 'a.rb')
        second_file = File.join(temporary_directory, 'b.rb')
        File.write(first_file, first_file_content)
        File.write(second_file, second_file_content)
        FileUtils.rm_f(File.join(temporary_directory, 'rbs_collection.lock.yaml'))
        FileUtils.rm_f('rbs_collection.lock.yaml')
        Dir.chdir(temporary_directory) do
          described_class.run([first_file])
        end
        expect(File.read(first_file)).to include('@return')
        expect(File.read(second_file)).not_to include('@return')
      end
    end

    it 'updates all files when given directory', :aggregate_failures do
      Dir.mktmpdir do |temporary_directory|
        first_file = File.join(temporary_directory, 'a.rb')
        second_file = File.join(temporary_directory, 'b.rb')
        File.write(first_file, first_file_content)
        File.write(second_file, second_file_content)
        described_class.run([temporary_directory])
        expect(File.read(first_file)).to include('@return')
        expect(File.read(second_file)).to include('@return')
      end
    end

    context 'when file does not exist' do
      let(:aggressive_options) do
        Docscribe::CLI::Options::DEFAULT.dup.merge(mode: :write, strategy: :aggressive, rbs_collection: true, no_boilerplate: true, keep_descriptions: true, rbs: true)
      end

      before do
        allow(File).to receive_messages(exist?: false, file?: false)
        allow(Docscribe::CLI::Options).to receive(:parse!).and_return(aggressive_options)
        allow(Docscribe::CLI::Run).to receive(:run).and_return(0)
      end

      it 'treats non-existent file path as directory (File.file? false)' do
        Dir.mktmpdir do |temporary_directory|
          nonexistent_path = File.join(temporary_directory, 'nonexistent.rb')
          described_class.send(:run_first_pass, nonexistent_path)
          expect(Docscribe::CLI::Options).to have_received(:parse!).with(array_including(nonexistent_path))
          expect(Docscribe::CLI::Run).to have_received(:run).with(argv: [nonexistent_path], options: anything)
        end
      end
    end
  end

  describe '.run orchestration' do
    context 'when first pass fails' do
      before do
        allow(described_class).to receive(:run_first_pass).and_return(2)
        allow(described_class).to receive(:run_second_pass)
      end

      it 'returns early and does not run second' do
        result = described_class.run(['.'])
        expect(result).to eq(2)
        expect(described_class).not_to have_received(:run_second_pass)
      end
    end

    context 'when first succeeds and second returns 1' do
      before do
        allow(described_class).to receive_messages(run_first_pass: 0, run_second_pass: 1)
      end

      it 'runs second pass and returns its exit code', :aggregate_failures do
        expect(described_class.run(['.'])).to eq(1)
        expect(described_class).to have_received(:run_second_pass)
      end
    end

    context 'when both passes succeed' do
      before do
        allow(described_class).to receive_messages(run_first_pass: 0, run_second_pass: 0)
      end

      it 'returns 0' do
        expect(described_class.run([])).to eq(0)
      end
    end

    it 'passes parsed target to both passes' do
      Dir.mktmpdir do |temporary_directory|
        target_file = File.join(temporary_directory, 'x.rb')
        FileUtils.touch(target_file)
        allow(described_class).to receive(:run_first_pass).with(target_file).and_return(0)
        allow(described_class).to receive(:run_second_pass).with(target_file).and_return(0)
        described_class.run([target_file])
        expect(described_class).to have_received(:run_first_pass).with(target_file)
        expect(described_class).to have_received(:run_second_pass).with(target_file)
      end
    end
  end
end
