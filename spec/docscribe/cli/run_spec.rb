# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'docscribe/cli'
require 'docscribe/server'

RSpec.describe Docscribe::CLI::Run do
  subject(:result) { Open3.capture3('ruby', exe, *args, chdir: dir) }

  let(:exe)      { File.expand_path('exe/docscribe') }
  let(:dir)      { Dir.mktmpdir }
  let(:code) do
    <<~RUBY
      class Foo
        def greet(name)
          "Hello, \#{name}"
        end

        def bar(x, y)
          x + y
        end
      end
    RUBY
  end

  before { File.write("#{dir}/foo.rb", code) }
  after  { FileUtils.remove_entry(dir) }

  describe 'check mode (default)' do
    let(:args) { ['foo.rb'] }

    it 'prints progress markers to stderr' do
      expect(result[1]).to include('F')
    end

    it 'prints Would update to stdout' do
      expect(result[0]).to match(/^Would update:/)
    end

    it 'does not print Would update to stderr' do
      expect(result[1]).not_to include('Would update')
    end

    it 'prints explanations before summary' do
      output = result[0]
      fail_idx = output.index('Would update:')
      status_idx = output.index('Docscribe:')
      expect(fail_idx).to be < status_idx
    end

    it 'prints change reasons' do
      expect(result[0]).to include('missing docs for Foo#bar')
    end

    it 'prints all change reasons' do
      expect(result[0]).to include('missing docs for Foo#greet')
    end

    it 'prints summary line' do
      expect(result[0]).to match(/Docscribe: (FAILED|OK)/)
    end

    it_behaves_like 'correct exit status'
  end

  describe 'check mode with --verbose' do
    let(:args) { %w[--verbose foo.rb] }

    it 'prints FAIL verdict per file to stderr' do
      expect(result[1]).to include('FAIL foo.rb')
    end

    it 'includes change reasons inline with verdict on stderr' do
      expect(result[1]).to match(/FAIL foo\.rb\n\s+- missing/)
    end

    it 'prints Would update without duplicating explanations' do
      output = result[0]
      after_would = output.split('Would update:').last || ''
      expect(after_would).not_to include('missing docs')
    end

    it 'prints summary line' do
      expect(result[0]).to match(/Docscribe: (FAILED|OK)/)
    end

    it 'outputs explanations to stderr' do
      expect(result[1]).to include('missing docs for Foo#bar')
    end

    it 'shows progress [N/total] on stderr' do
      expect(result[1]).to include('[1/1] foo.rb')
    end

    it_behaves_like 'correct exit status'
  end

  describe 'check mode with --progress' do
    let(:args) { %w[--progress foo.rb] }

    it 'shows progress [N/total] on stderr' do
      expect(result[1]).to include('[1/1] foo.rb')
    end

    it 'still prints progress markers to stderr alongside progress' do
      expect(result[1]).to include('[1/1]').and include('F')
    end

    it 'prints Would update to stdout' do
      expect(result[0]).to match(/^Would update:/)
    end

    it_behaves_like 'correct exit status'
  end

  describe 'check mode with --progress --quiet' do
    let(:args) { %w[--progress --quiet foo.rb] }

    it 'shows progress even when quiet' do
      expect(result[1]).to include('[1/1] foo.rb')
    end

    it 'prints Would update to stdout' do
      expect(result[0]).to match(/^Would update:/)
    end
  end

  describe 'write mode with --progress' do
    let(:args) { %w[--progress -a foo.rb] }

    it 'shows progress on stderr' do
      expect(result[1]).to include('[1/1] foo.rb')
    end

    it 'prints C marker to stderr' do
      expect(result[1]).to include('C')
    end

    it 'prints update summary to stdout' do
      expect(result[0]).to match(/updated \d+ file/)
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end
  end

  describe 'check mode with --explain' do
    let(:args) { %w[--explain foo.rb] }

    it 'prints change reasons in summary (same as default)' do
      expect(result[0]).to include('missing docs for Foo#bar')
    end

    it 'prints Would update before summary' do
      output = result[0]
      fail_idx = output.index('Would update:')
      status_idx = output.index('Docscribe:')
      expect(fail_idx).to be < status_idx
    end

    it_behaves_like 'correct exit status'
  end

  describe 'check mode with --quiet' do
    let(:args) { %w[--quiet foo.rb] }

    it 'prints Would update to stdout' do
      expect(result[0]).to match(/^Would update:/)
    end

    it 'does not print change reasons in summary' do
      output = result[0]
      expect(output).not_to include('missing docs')
    end

    it_behaves_like 'correct exit status'
  end

  describe 'write mode with --quiet' do
    let(:args) { %w[-a --quiet foo.rb] }

    it 'prints C marker to stderr' do
      expect(result[1]).to include('C')
    end

    it 'prints Updated:' do
      expect(result[0]).to include('Updated:')
    end

    it 'does not print change reasons in write mode' do
      expect(result[0]).not_to include('missing docs')
    end

    it 'prints update summary to stdout' do
      expect(result[0]).to match(/updated \d+ file/)
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end
  end

  describe 'write mode' do
    let(:args) { %w[-a foo.rb] }

    it 'prints C marker to stderr' do
      expect(result[1]).to include('C')
    end

    it 'prints update summary to stdout' do
      expect(result[0]).to match(/updated \d+ file/)
    end

    it 'prints Updated: per corrected file' do
      expect(result[0]).to include('Updated:')
    end

    it 'prints change reasons with Updated:' do
      expect(result[0]).to match(/Updated: .*\n\s+- missing/)
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end

    it 'actually writes docs to file' do
      Open3.capture3('ruby', exe, '-a', 'foo.rb', chdir: dir)
      content = File.read("#{dir}/foo.rb")
      expect(content).to include('@param [Object] name')
    end
  end

  describe 'write mode with --verbose' do
    let(:args) { %w[-a --verbose foo.rb] }

    it 'prints CHANGED verdict with explanations to stderr' do
      expect(result[1]).to match(/CHANGED foo\.rb\n\s+- missing/)
    end

    it 'prints update summary to stdout' do
      expect(result[0]).to match(/updated \d+ file/)
    end

    it 'prints Updated: without duplicating reasons' do
      after_updated = result[0].split('Updated:').last || ''
      expect(after_updated).not_to include('missing docs')
    end
  end

  describe 'with --format json' do
    let(:args) { %w[--format json foo.rb] }

    it 'outputs valid JSON to stdout' do
      expect { JSON.parse(result[0]) }.not_to raise_error
    end

    it 'includes metadata in JSON' do
      parsed = JSON.parse(result[0])
      expect(parsed['metadata']).to include('docscribe_version', 'ruby_version')
    end

    it 'includes files array in JSON' do
      expect(JSON.parse(result[0])['files']).to be_an(Array)
    end

    it 'includes offenses in first file' do
      expect(JSON.parse(result[0])['files'][0]['offenses']).not_to be_empty
    end

    it 'includes summary in JSON' do
      parsed = JSON.parse(result[0])
      expect(parsed['summary']).to include('offense_count', 'target_file_count', 'inspected_file_count')
    end

    it 'has correct cop_name in offenses' do
      offenses = JSON.parse(result[0])['files'].flat_map { |f| f['offenses'] }
      expect(offenses.first['cop_name']).to match(%r{\ADocscribe/})
    end

    it 'still sends progress markers to stderr' do
      expect(result[1]).to include('F')
    end

    it 'exits 1 with findings' do
      expect(result[2].exitstatus).to eq(1)
    end

    it 'does not contain Would update on stdout' do
      expect(result[0]).not_to include('Would update:')
    end

    it 'does not contain Docscribe: summary on stdout' do
      expect(result[0]).not_to include('Docscribe:')
    end
  end

  describe 'with --format json --verbose' do
    let(:args) { %w[--format json --verbose foo.rb] }

    it 'still outputs JSON to stdout' do
      expect { JSON.parse(result[0]) }.not_to raise_error
    end

    it 'prints FAIL verdict to stderr' do
      expect(result[1]).to include('FAIL foo.rb')
    end
  end

  describe 'with --format json --quiet' do
    let(:args) { %w[--format json --quiet foo.rb] }

    it 'does not contain Would update on stdout' do
      expect(result[0]).not_to include('Would update:')
    end

    it 'does not contain Docscribe: summary on stdout' do
      expect(result[0]).not_to include('Docscribe:')
    end
  end

  describe 'with --format json in write mode' do
    let(:args) { %w[--format json -a foo.rb] }

    it 'outputs valid JSON to stdout' do
      expect { JSON.parse(result[0]) }.not_to raise_error
    end

    it 'includes one file in JSON' do
      expect(JSON.parse(result[0])['files'].size).to eq(1)
    end

    it 'has correct file path' do
      expect(JSON.parse(result[0])['files'][0]['path']).to eq('foo.rb')
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end

    it 'sends C progress to stderr' do
      expect(result[1]).to include('C')
    end
  end

  describe 'with --format json when all files fine' do
    let(:code) { <<~RUBY }
      # documented
      class Foo; end
    RUBY

    let(:args) { %w[--format json foo.rb] }

    it 'outputs JSON with empty files' do
      parsed = JSON.parse(result[0])
      expect(parsed['files']).to eq([])
    end

    it 'outputs OK status in JSON summary' do
      parsed = JSON.parse(result[0])
      expect(parsed['summary']['offense_count']).to eq(0)
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end
  end

  describe 'with --format json and overlapping path arguments' do
    let(:abs_path) { File.join(dir, 'foo.rb') }

    describe 'mixed absolute and relative spellings of one file' do
      let(:args) { ['--format', 'json', abs_path, 'foo.rb'] }
      let(:parsed) { JSON.parse(result[0]) }

      it 'lists one file entry' do
        expect(parsed['files'].size).to eq(1)
      end

      it 'keeps every offense of that file' do
        expect(parsed['files'][0]['offenses'].size).to eq(2)
      end

      it 'counts the file and its offenses once' do
        expect(parsed['summary']).to include('target_file_count' => 1, 'offense_count' => 2)
      end

      it 'keeps the first spelling of the path' do
        expect(parsed['files'][0]['path']).to eq(abs_path)
      end
    end

    describe 'a directory argument overlapping a file argument' do
      let(:args) { ['--format', 'json', dir, abs_path] }
      let(:parsed) { JSON.parse(result[0]) }

      it 'lists one file entry' do
        expect(parsed['files'].size).to eq(1)
      end

      it 'keeps every offense of that file' do
        expect(parsed['files'][0]['offenses'].size).to eq(2)
      end
    end

    describe 'two distinct files' do
      before { File.write(File.join(dir, 'bar.rb'), code) }

      let(:args) { ['--format', 'json', 'foo.rb', './bar.rb'] }
      let(:parsed) { JSON.parse(result[0]) }

      it 'lists one entry per file' do
        expect(parsed['files'].size).to eq(2)
      end

      it 'keeps every offense across files' do
        expect(parsed['summary']['offense_count']).to eq(4)
      end
    end
  end

  describe 'with --format sarif and overlapping path arguments' do
    let(:abs_path) { File.join(dir, 'foo.rb') }
    let(:args) { ['--format', 'sarif', abs_path, 'foo.rb'] }
    let(:parsed) { JSON.parse(result[0]) }

    it 'produces one result per offense, not per spelling' do
      expect(parsed['runs'][0]['results'].size).to eq(2)
    end

    it 'carries a type property on every result' do
      types = parsed['runs'][0]['results'].map { |r| r['properties']['type'] }
      expect(types).to all(be_a(String))
    end
  end

  context 'when all files are fine' do
    let(:code) { <<~RUBY }
      # documentation
      class Foo; end
    RUBY

    let(:args) { ['foo.rb'] }

    it 'prints dot marker to stderr' do
      expect(result[1]).to include('.')
    end

    it 'prints OK summary to stdout' do
      expect(result[0]).to include('Docscribe: OK')
    end

    it 'exits 0' do
      expect(result[2].exitstatus).to eq(0)
    end
  end

  describe '.expand_paths' do
    it 'returns one entry for an absolute and a relative spelling of one file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'a.rb')
        File.write(path, '')
        expect(Dir.chdir(dir) { described_class.send(:expand_paths, [path, 'a.rb']) }).to eq([path])
      end
    end

    it 'returns one entry for ./-prefixed and bare spellings' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.rb'), '')
        expect(Dir.chdir(dir) { described_class.send(:expand_paths, ['./a.rb', 'a.rb']) }).to eq(['./a.rb'])
      end
    end

    it 'returns one entry when a file is also covered by a directory argument' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'a.rb')
        File.write(path, '')
        File.write(File.join(dir, 'b.rb'), '')
        expanded = described_class.send(:expand_paths, [dir, path])
        expect(expanded).to eq([path, File.join(dir, 'b.rb')].sort)
      end
    end

    it 'returns one entry for a symlinked spelling of one file' do
      Dir.mktmpdir do |dir|
        real = File.join(dir, 'real.rb')
        link = File.join(dir, 'link.rb')
        File.write(real, '')
        File.symlink(real, link)
        expect(described_class.send(:expand_paths, [real, link]).size).to eq(1)
      end
    end

    it 'keeps distinct files' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.rb'), '')
        File.write(File.join(dir, 'b.rb'), '')
        expect(described_class.send(:expand_paths, [dir]).size).to eq(2)
      end
    end

    it 'sorts the result deterministically' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'b.rb'), '')
        File.write(File.join(dir, 'a.rb'), '')
        expect(described_class.send(:expand_paths, [dir])).to eq([File.join(dir, 'a.rb'), File.join(dir, 'b.rb')])
      end
    end
  end

  describe '.ensure_server_running!' do
    it 'delegates to Docscribe::Server.ensure_running!' do
      allow(Docscribe::Server).to receive(:ensure_running!)
      described_class.send(:ensure_server_running!, config_path: nil)
      expect(Docscribe::Server).to have_received(:ensure_running!).with(config_path: nil)
    end
  end

  describe '.handle_validated_type_mismatch' do
    subject(:handle) do
      described_class.send(:handle_validated_type_mismatch, 'a.rb', changes, changes, ctx)
    end

    let(:changes) { [{ type: :updated_return, line: 3, method: 'A#foo' }] }
    let(:state) do
      { checked_fail: 0, changed: false, fail_paths: [], fail_changes: {},
        type_mismatch_paths: [], type_mismatch_changes: {} }
    end
    let(:ctx) { { display_path: 'shown/a.rb', options: { verbose: false }, state: state } }

    it 'counts the failure and keeps the path listed', :aggregate_failures do
      handle
      expect(state[:checked_fail]).to eq(1)
      expect(state[:changed]).to be(true)
      expect(state[:fail_paths]).to eq(['a.rb'])
    end

    it 'drops tracked records from fail changes' do
      handle
      expect(state[:fail_changes]).to eq({ 'a.rb' => [] })
    end

    it 'tracks mismatches once, keyed by raw path' do
      handle
      expect(state[:type_mismatch_paths]).to eq(['a.rb'])
      expect(state[:type_mismatch_changes]).to eq({ 'a.rb' => changes })
    end

    it 'prints the failure marker' do
      expect { handle }.to output('F').to_stderr
    end
  end

  describe '.extract_cli_overrides' do
    context 'when options contain false values' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) { { keep_descriptions: true, no_boilerplate: false, rbs: false, validate_types: false } }

      it 'filters false values for non-negatable flags', :aggregate_failures do
        expect(overrides).not_to have_key('no_boilerplate')
        expect(overrides).not_to have_key('rbs')
      end

      it 'keeps explicit false for [no-] flags so it overrides config true' do
        expect(overrides['validate_types']).to be(false)
      end

      it 'keeps true values' do
        expect(overrides).to have_key('keep_descriptions')
        expect(overrides['keep_descriptions']).to be(true)
      end
    end

    context 'when options contain nil values' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) { { keep_descriptions: nil, no_boilerplate: true, rbs: nil } }

      it 'filters nil values' do
        expect(overrides).not_to have_key('keep_descriptions')
        expect(overrides).not_to have_key('rbs')
      end

      it 'keeps non-nil true' do
        expect(overrides['no_boilerplate']).to be(true)
      end
    end

    context 'when options contain empty arrays' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) { { include: [], exclude: [], sig_dirs: [], include_file: ['a.rb'], exclude_file: [] } }

      it 'filters empty arrays', :aggregate_failures do
        expect(overrides).not_to have_key('include')
        expect(overrides).not_to have_key('exclude')
        expect(overrides).not_to have_key('sig_dirs')
        expect(overrides).not_to have_key('exclude_file')
      end

      it 'keeps non-empty arrays' do
        expect(overrides['include_file']).to eq(['a.rb'])
      end
    end

    context 'when options contain valid arrays' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) { { include: ['lib/**/*.rb'], exclude: ['spec/**/*'], sig_dirs: ['sig'], rbi_dirs: ['sorbet/rbi'] } }

      it 'keeps valid arrays', :aggregate_failures do
        expect(overrides['include']).to eq(['lib/**/*.rb'])
        expect(overrides['exclude']).to eq(['spec/**/*'])
        expect(overrides['sig_dirs']).to eq(['sig'])
        expect(overrides['rbi_dirs']).to eq(['sorbet/rbi'])
      end
    end

    context 'when options contain non-override keys' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) { { keep_descriptions: true, unrelated: 'value', mode: :check } }

      it 'slices only CLI_OVERRIDE_KEYS', :aggregate_failures do
        expect(overrides).to have_key('keep_descriptions')
        expect(overrides).not_to have_key('unrelated')
        expect(overrides).not_to have_key('mode')
      end
    end

    context 'when options are mixed' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) do
        {
          keep_descriptions: true,
          no_boilerplate: false,
          include: [],
          exclude: ['excluded.rb'],
          rbs: true,
          rbs_collection: false,
          sig_dirs: ['sig'],
          sorbet: nil,
          rbi_dirs: [],
          validate_types: true
        }
      end

      it 'correctly filters and keeps', :aggregate_failures do
        expect(overrides).to include('keep_descriptions' => true, 'exclude' => ['excluded.rb'], 'rbs' => true, 'sig_dirs' => ['sig'], 'validate_types' => true)
        expect(overrides).not_to have_key('no_boilerplate')
        expect(overrides).not_to have_key('include')
        expect(overrides).not_to have_key('rbs_collection')
        expect(overrides).not_to have_key('sorbet')
        expect(overrides).not_to have_key('rbi_dirs')
      end

      it 'stringifies keys' do
        expect(overrides.keys).to all(be_a(String))
      end
    end

    context 'when options are empty' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) { {} }

      it 'returns empty hash' do
        expect(overrides).to eq({})
      end
    end

    context 'when options contain empty string vs false' do
      subject(:overrides) { described_class.send(:extract_cli_overrides, options) }

      let(:options) { { keep_descriptions: '', rbs: false } }

      it 'keeps empty string but filters false', :aggregate_failures do
        expect(overrides).to have_key('keep_descriptions')
        expect(overrides['keep_descriptions']).to eq('')
        expect(overrides).not_to have_key('rbs')
      end
    end
  end

  describe '--parallel' do
    before do
      %w[a b c].each { |n| File.write("#{dir}/#{n}.rb", code) }
    end

    it 'reports the same result as a sequential run' do
      _o, seq_err, seq_status = Open3.capture3('ruby', exe, 'a.rb', 'b.rb', 'c.rb', chdir: dir)
      _po, par_err, par_status = Open3.capture3('ruby', exe, '--jobs', '2', 'a.rb', 'b.rb', 'c.rb', chdir: dir)

      expect(par_status.exitstatus).to eq(seq_status.exitstatus)
      expect(par_err.scan(/(\d+) files? checked/)).to eq(seq_err.scan(/(\d+) files? checked/))
    end

    it 'implies --parallel when --jobs is given' do
      out, _err, status = Open3.capture3('ruby', exe, '--jobs', '2', 'a.rb', 'b.rb', 'c.rb', chdir: dir)

      expect(status.exitstatus).to eq(1)
      expect(out).to include('3 need updates')
    end

    it 'treats --jobs 1 as sequential' do
      out, _err, status = Open3.capture3('ruby', exe, '--jobs', '1', 'a.rb', 'b.rb', 'c.rb', chdir: dir)

      expect(status.exitstatus).to eq(1)
      expect(out).to include('3 need updates')
    end
  end
end
