# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI::CheckForComments do
  describe '.resolve_placeholders' do
    it 'returns default_message and param_documentation from config' do
      config = instance_double(
        Docscribe::Config,
        raw: { 'doc' => nil },
        param_documentation: 'Param documentation.'
      )
      result = described_class.send(:resolve_placeholders, config)
      expect(result).to include('Method documentation.', 'Param documentation.')
    end

    it 'returns unique values only' do
      config = instance_double(
        Docscribe::Config,
        raw: { 'doc' => { 'default_message' => 'Some text' } },
        param_documentation: 'Some text'
      )
      result = described_class.send(:resolve_placeholders, config)
      expect(result).to eq(['Some text'])
    end

    it 'returns empty array when no placeholders configured' do
      config = instance_double(
        Docscribe::Config,
        raw: { 'doc' => nil },
        param_documentation: nil
      )
      result = described_class.send(:resolve_placeholders, config)
      expect(result).to eq(['Method documentation.'])
    end
  end

  describe '.raw_or_default' do
    it 'falls back to DEFAULT when raw is nil' do
      config = instance_double(
        Docscribe::Config,
        raw: { 'doc' => nil },
        param_documentation: nil
      )
      result = described_class.send(:raw_or_default, config, %w[doc default_message])
      expect(result).to eq('Method documentation.')
    end

    it 'returns raw value when present' do
      config = instance_double(
        Docscribe::Config,
        raw: { 'doc' => { 'default_message' => 'Custom text' } },
        param_documentation: nil
      )
      result = described_class.send(:raw_or_default, config, %w[doc default_message])
      expect(result).to eq('Custom text')
    end
  end

  describe '.expand_paths' do
    it 'includes .rb files from directories' do
      Dir.mktmpdir do |dir|
        File.write("#{dir}/a.rb", '')
        File.write("#{dir}/b.rb", '')
        result = described_class.send(:expand_paths, [dir])
        expect(result.size).to eq(2)
      end
    end

    it 'includes explicit .rb file paths' do
      Dir.mktmpdir do |dir|
        File.write("#{dir}/a.rb", '')
        result = described_class.send(:expand_paths, ["#{dir}/a.rb"])
        expect(result).to eq(["#{dir}/a.rb"])
      end
    end
  end

  describe '.expand_single_path' do
    let(:files) { [] }

    it 'warns on missing paths' do
      expect { described_class.send(:expand_single_path, files, '/nonexistent') }
        .to output(/Skipping missing/).to_stderr
    end

    it 'warns on non-Ruby files' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/file.txt"
        File.write(path, '')
        expect { described_class.send(:expand_single_path, files, path) }
          .to output(/Skipping non-Ruby/).to_stderr
      end
    end
  end

  describe '.scan_file' do
    it 'finds placeholder in comment lines' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/test.rb"
        File.write(path, "# Method documentation.\ndef foo; end\n")
        result = described_class.send(:scan_file, path, ['Method documentation.'])
        expect(result).to eq([path, [[1, '# Method documentation.']]])
      end
    end

    it 'returns nil when no matches' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/test.rb"
        File.write(path, "# Real doc\ndef foo; end\n")
        result = described_class.send(:scan_file, path, ['Method documentation.'])
        expect(result).to be_nil
      end
    end

    it 'ignores non-comment lines' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/test.rb"
        File.write(path, "x = 'Method documentation.'\n")
        result = described_class.send(:scan_file, path, ['Method documentation.'])
        expect(result).to be_nil
      end
    end

    it 'matches multiple placeholders in one file' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/test.rb"
        File.write(path, "# Method documentation.\n# Param documentation.\ndef foo; end\n")
        result = described_class.send(:scan_file, path, ['Method documentation.', 'Param documentation.'])
        expect(result[1].size).to eq(2)
      end
    end
  end

  describe '.scan_paths' do
    it 'returns results for files with matches' do
      Dir.mktmpdir do |dir|
        path1 = "#{dir}/a.rb"
        path2 = "#{dir}/b.rb"
        File.write(path1, "# Method documentation.\n")
        File.write(path2, "# Real doc\n")
        results = described_class.send(:scan_paths, [path1, path2], ['Method documentation.'])
        expect(results.size).to eq(1)
        expect(results[0][0]).to eq(path1)
      end
    end
  end

  describe '.no_placeholders_configured' do
    it 'returns 0 and warns' do
      expect { expect(described_class.send(:no_placeholders_configured)).to eq(0) }
        .to output(/No placeholder messages/).to_stderr
    end
  end

  describe '.run' do
    it 'returns 1 when no files found' do
      Dir.mktmpdir do |dir|
        result = described_class.run([dir])
        expect(result).to eq(1)
      end
    end

    it 'returns 0 when no placeholders found' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/test.rb"
        File.write(path, "# Real documentation\ndef foo; end\n")
        result = described_class.run([dir])
        expect(result).to eq(0)
      end
    end

    it 'returns 1 when placeholders found' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/test.rb"
        File.write(path, "# Method documentation.\ndef foo; end\n")
        result = described_class.run([dir])
        expect(result).to eq(1)
      end
    end

    it 'reports found placeholders to stdout' do
      Dir.mktmpdir do |dir|
        path = "#{dir}/test.rb"
        File.write(path, "# Method documentation.\ndef foo; end\n")
        output = capture_stdout { described_class.run([dir]) }
        expect(output).to include('Found 1 placeholder(s)')
        expect(output).to include(path)
      end
    end
  end

  describe 'CLI integration' do
    subject(:result) { Open3.capture3('ruby', exe, 'check_for_comments', *args) }

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
