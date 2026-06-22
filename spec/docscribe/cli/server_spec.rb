# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'securerandom'
require 'rbconfig'

RSpec.describe 'docscribe server subcommand' do
  def exe
    File.expand_path('../../../exe/docscribe', __dir__)
  end

  describe 'without arguments' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    it 'prints usage to stderr' do
      _out, err, st = Open3.capture3(RbConfig.ruby, exe, 'server', chdir: dir)
      expect(err).to include('Usage: docscribe server <command>')
      expect(st.exitstatus).to eq(1)
    end
  end

  describe 'status' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    it 'reports not running initially' do
      _out, err, st = Open3.capture3(RbConfig.ruby, exe, 'server', 'status', chdir: dir)
      expect(err).to include('not running')
      expect(st.exitstatus).to eq(0)
    end
  end

  describe 'start' do
    before(:context) do
      @exe = File.expand_path('../../../exe/docscribe', __dir__)
      @dir = Dir.mktmpdir
      _, @start_err, @start_st = Open3.capture3(RbConfig.ruby, @exe, 'server', 'start', chdir: @dir)
    end

    after(:context) do
      Open3.capture3(RbConfig.ruby, @exe, 'server', 'stop', chdir: @dir)
      FileUtils.remove_entry(@dir) if @dir
    end

    it 'starts the server and reports success' do
      expect(@start_err).to match(/started/)
      expect(@start_st.exitstatus).to eq(0)
    end

    it 'makes the server accessible for status' do
      _, err, st = Open3.capture3(RbConfig.ruby, @exe, 'server', 'status', chdir: @dir)
      expect(err).to include('running')
      expect(st.exitstatus).to eq(0)
    end

    it 'reports already running on second start' do
      _, err, st = Open3.capture3(RbConfig.ruby, @exe, 'server', 'start', chdir: @dir)
      expect(err).to include('already running')
      expect(st.exitstatus).to eq(0)
    end
  end

  describe 'stop' do
    let(:dir) { Dir.mktmpdir }

    after do
      Open3.capture3(RbConfig.ruby, exe, 'server', 'stop', chdir: dir)
      FileUtils.remove_entry(dir)
    end

    it 'reports not running when no server' do
      _out, err, st = Open3.capture3(RbConfig.ruby, exe, 'server', 'stop', chdir: dir)
      expect(err).to include('not running')
      expect(st.exitstatus).to eq(0)
    end

    it 'stops a running server' do
      _out, err, st = Open3.capture3(RbConfig.ruby, exe, 'server', 'start', chdir: dir)
      expect(st.exitstatus).to eq(0), "start failed: #{err}"

      _out, stop_err, stop_st = Open3.capture3(RbConfig.ruby, exe, 'server', 'stop', chdir: dir)
      expect(stop_err).to include('stopped')
      expect(stop_st.exitstatus).to eq(0)
    end
  end

  describe 'start/stop lifecycle' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    it 'allows status changes from not running to running to not running' do
      _, err1, = Open3.capture3(RbConfig.ruby, exe, 'server', 'status', chdir: dir)
      expect(err1).to include('not running')

      Open3.capture3(RbConfig.ruby, exe, 'server', 'start', chdir: dir)

      _, err2, = Open3.capture3(RbConfig.ruby, exe, 'server', 'status', chdir: dir)
      expect(err2).to include('running')

      Open3.capture3(RbConfig.ruby, exe, 'server', 'stop', chdir: dir)

      _, err3, = Open3.capture3(RbConfig.ruby, exe, 'server', 'status', chdir: dir)
      expect(err3).to include('not running')
    end
  end
end

RSpec.describe 'docscribe --server flag' do
  before(:context) do
    @exe = File.expand_path('../../../exe/docscribe', __dir__)
    @dir = Dir.mktmpdir
    _, @start_err, @start_st = Open3.capture3(RbConfig.ruby, @exe, 'server', 'start', chdir: @dir)
    raise "Failed to start server: #{@start_err}" unless @start_st&.exitstatus == 0
  end

  after(:context) do
    Open3.capture3(RbConfig.ruby, @exe, 'server', 'stop', chdir: @dir)
    FileUtils.remove_entry(@dir) if @dir
  end

  let(:file) { "#{@dir}/#{SecureRandom.hex(8)}.rb" }

  before do
    File.write(file, <<~RUBY)
      def hello
        puts 'world'
      end
    RUBY
  end

  it 'returns findings from the server' do
    out, _err, st = Open3.capture3(RbConfig.ruby, @exe, '--server', 'check', file, chdir: @dir)
    expect(out).to include('Would update:')
    expect(st.exitstatus).to eq(1)
  end

  context 'with --autocorrect' do
    it 'applies fixes via the server' do
      _out, _err, st = Open3.capture3(RbConfig.ruby, @exe, '--server', '-a', file, chdir: @dir)
      expect(st.exitstatus).to eq(0)

      updated = File.read(file)
      expect(updated).to include('@return')
    end
  end

  context 'with --quiet' do
    it 'does not print change details' do
      out, _err, _st = Open3.capture3(RbConfig.ruby, @exe, '--server', '--quiet', 'check', file, chdir: @dir)
      expect(out).to include('Would update:')
      expect(out).not_to include('missing docs')
    end
  end
end
