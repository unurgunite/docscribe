# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'docscribe/cli/coverage'

RSpec.describe Docscribe::CLI::Coverage do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  describe '.run' do
    it 'returns 0 with --help' do
      expect(described_class.run(%w[--help])).to be(0)
    end

    it 'prints Documentation Coverage Report header' do
      File.write(File.join(tmpdir, 't.rb'), "# doc\n# @return [Integer]\ndef foo; 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb')]) })
        .to include('Documentation Coverage Report')
    end

    it 'prints Methods in text report' do
      File.write(File.join(tmpdir, 't.rb'), "# doc\n# @return [Integer]\ndef foo; 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb')]) })
        .to include('Methods:')
    end

    it 'prints Params in text report' do
      File.write(File.join(tmpdir, 't.rb'), "# doc\n# @return [Integer]\ndef foo; 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb')]) })
        .to include('Params:')
    end

    it 'prints Returns in text report' do
      File.write(File.join(tmpdir, 't.rb'), "# doc\n# @return [Integer]\ndef foo; 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb')]) })
        .to include('Returns:')
    end

    it 'includes methods key in JSON output' do
      File.write(File.join(tmpdir, 't.rb'), "def foo(x, y); 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb'), '--format', 'json']) })
        .to include('"methods"')
    end

    it 'includes params key in JSON output' do
      File.write(File.join(tmpdir, 't.rb'), "def foo(x, y); 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb'), '--format', 'json']) })
        .to include('"params"')
    end

    it 'includes returns key in JSON output' do
      File.write(File.join(tmpdir, 't.rb'), "def foo(x, y); 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb'), '--format', 'json']) })
        .to include('"returns"')
    end

    it 'includes coverage key in JSON output' do
      File.write(File.join(tmpdir, 't.rb'), "def foo(x, y); 42; end\n")
      expect(capture_stdout { described_class.run([File.join(tmpdir, 't.rb'), '--format', 'json']) })
        .to include('"coverage"')
    end

    it 'handles directory expansion' do
      File.write(File.join(tmpdir, 'a.rb'), 'def foo; end')
      File.write(File.join(tmpdir, 'b.rb'), 'def bar; end')
      expect(capture_stdout { described_class.run([tmpdir]) }).to include('Methods:')
    end
  end

  describe Docscribe::CLI::Coverage::CoverageStats do
    describe '#method_coverage' do
      it 'returns 100.0 when total_methods is zero' do
        stats = described_class.new(
          total_methods: 0, documented_methods: 0, total_params: 0, documented_params: 0, total_returns: 0,
          documented_returns: 0
        )
        expect(stats.method_coverage).to eq(100.0)
      end

      it 'calculates percentage with partial coverage' do
        stats = described_class.new(
          total_methods: 4, documented_methods: 3, total_params: 0, documented_params: 0, total_returns: 0,
          documented_returns: 0
        )
        expect(stats.method_coverage).to eq(75.0)
      end
    end

    describe '#param_coverage' do
      it 'returns 100.0 when total_params is zero' do
        stats = described_class.new(
          total_methods: 5, documented_methods: 5, total_params: 0, documented_params: 0, total_returns: 0,
          documented_returns: 0
        )
        expect(stats.param_coverage).to eq(100.0)
      end

      it 'calculates percentage with partial coverage' do
        stats = described_class.new(
          total_methods: 1, documented_methods: 1, total_params: 4, documented_params: 2, total_returns: 0,
          documented_returns: 0
        )
        expect(stats.param_coverage).to eq(50.0)
      end
    end

    describe '#return_coverage' do
      it 'returns 100.0 when total_returns is zero' do
        stats = described_class.new(
          total_methods: 0, documented_methods: 0, total_params: 0, documented_params: 0, total_returns: 0,
          documented_returns: 0
        )
        expect(stats.return_coverage).to eq(100.0)
      end

      it 'calculates percentage with partial coverage' do
        stats = described_class.new(
          total_methods: 10, documented_methods: 10, total_params: 0, documented_params: 0, total_returns: 10,
          documented_returns: 7
        )
        expect(stats.return_coverage).to eq(70.0)
      end
    end
  end
end
