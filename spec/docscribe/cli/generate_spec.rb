# frozen_string_literal: true

require 'tmpdir'
require 'docscribe/cli/generate'

RSpec.describe Docscribe::CLI::Generate do
  def run(*argv)
    described_class.run(argv)
  end

  describe 'argument validation' do
    it 'returns 1 and warns when type is missing' do
      expect { expect(run).to eq(1) }.to output(/required/).to_stderr
    end

    it 'returns 1 and warns when class name is missing' do
      expect { expect(run('tag')).to eq(1) }.to output(/required/).to_stderr
    end

    it 'returns 1 for unknown plugin type' do
      expect { expect(run('unknown', 'MyPlugin')).to eq(1) }
        .to output(/unknown type/).to_stderr
    end

    it 'returns 1 for invalid constant name' do
      expect { expect(run('tag', 'not_valid')).to eq(1) }
        .to output(/not a valid Ruby constant/).to_stderr
    end
  end

  describe '--stdout' do
    it 'prints a TagPlugin skeleton to stdout' do
      expect { expect(run('tag', 'MyPlugin', '--stdout')).to eq(0) }
        .to output(/MyPlugin.*TagPlugin/m).to_stdout
    end

    it 'prints a CollectorPlugin skeleton to stdout' do
      expect { expect(run('collector', 'MyCollector', '--stdout')).to eq(0) }
        .to output(/MyCollector.*CollectorPlugin/m).to_stdout
    end

    it 'includes the class name in the tag template' do
      expect { run('tag', 'SincePlugin', '--stdout') }
        .to output(/class SincePlugin/).to_stdout
    end

    it 'includes the class name in the collector template' do
      expect { run('collector', 'AssocPlugin', '--stdout') }
        .to output(/class AssocPlugin/).to_stdout
    end
  end

  describe 'file generation' do
    it 'writes a TagPlugin file to the output directory' do
      Dir.mktmpdir do |dir|
        status = run('tag', 'SincePlugin', '--output', dir)
        expect(status).to eq(0)

        path = File.join(dir, 'since_plugin.rb')
        expect(File).to exist(path)
        expect(File.read(path)).to include('class SincePlugin')
        expect(File.read(path)).to include('TagPlugin')
      end
    end

    it 'writes a CollectorPlugin file to the output directory' do
      Dir.mktmpdir do |dir|
        status = run('collector', 'AssocPlugin', '--output', dir)
        expect(status).to eq(0)

        path = File.join(dir, 'assoc_plugin.rb')
        expect(File).to exist(path)
        expect(File.read(path)).to include('class AssocPlugin')
        expect(File.read(path)).to include('CollectorPlugin')
      end
    end

    it 'returns 1 and warns if the file already exists' do
      Dir.mktmpdir do |dir|
        run('tag', 'SincePlugin', '--output', dir)

        expect { expect(run('tag', 'SincePlugin', '--output', dir)).to eq(1) }
          .to output(/already exists/).to_stderr
      end
    end

    it 'creates the output directory if it does not exist' do
      Dir.mktmpdir do |dir|
        nested = File.join(dir, 'lib', 'plugins')
        run('tag', 'MyPlugin', '--output', nested)
        expect(File).to exist(File.join(nested, 'my_plugin.rb'))
      end
    end
  end

  describe 'snake_case file naming' do
    it 'converts CamelCase to snake_case for the filename' do
      Dir.mktmpdir do |dir|
        run('tag', 'ApiTagPlugin', '--output', dir)
        expect(File).to exist(File.join(dir, 'api_tag_plugin.rb'))
      end
    end

    it 'handles single-word names' do
      Dir.mktmpdir do |dir|
        run('collector', 'Associations', '--output', dir)
        expect(File).to exist(File.join(dir, 'associations.rb'))
      end
    end
  end
end
