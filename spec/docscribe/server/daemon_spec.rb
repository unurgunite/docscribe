# frozen_string_literal: true

require 'docscribe/server'
require 'fileutils'
require 'tmpdir'

RSpec.describe Docscribe::Server::Daemon do
  let!(:socket_path) { "#{Dir.mktmpdir}/docscribe-test.sock" }
  let!(:test_file) do
    path = "#{File.dirname(socket_path)}/test.rb"
    File.write(path, <<~RUBY)
      def hello
        puts 'world'
      end
    RUBY
    path
  end

  let!(:daemon) { described_class.new(socket_path: socket_path, idle_timeout: 60) }
  let!(:daemon_thread) { Thread.new { daemon.start } }
  let(:client) { Docscribe::Server::Client.new(socket_path) }

  before { sleep 0.5 }

  after do
    suppress_error { Docscribe::Server::Client.new(socket_path).shutdown }
    suppress_error { daemon_thread.join(3) }
    FileUtils.remove_entry(File.dirname(socket_path))
  end

  describe '#start' do
    it 'creates a socket file' do
      aggregate_failures do
        expect(File.exist?(socket_path)).to be true
        expect(File.exist?("#{socket_path}.pid")).to be true
      end
    end
  end

  describe 'check request' do
    subject(:response) { client.check(file: checked_file) }

    let(:checked_file) { test_file }

    context 'with a clean file' do
      let(:checked_file) { create_clean_file(socket_path) }

      it 'returns ok for a file with no issues' do
        aggregate_failures do
          expect(response).not_to be_nil
          expect(response['result'].slice('status', 'changed')).to eq('status' => 'ok', 'changed' => false)
        end
      end
    end

    context 'with a nonexistent file' do
      let(:checked_file) { '/nonexistent.rb' }

      it 'returns error for a nonexistent file' do
        aggregate_failures do
          expect(response).not_to be_nil
          expect(response.dig('error', 'message')).to include('File not found')
        end
      end
    end

    it 'returns fail for a file needing updates' do
      aggregate_failures do
        expect(response).not_to be_nil
        expect(response['result']['status']).to eq('fail')
      end
    end

    it 'defaults to safe strategy when not specified', :aggregate_failures do
      expect(response).not_to be_nil
      expect(response['error']).to be_nil
      expect(response['result']).to have_key('status')
    end
  end

  describe 'fix request' do
    subject(:response) { client.fix(file: test_file) }

    it 'returns success status' do
      aggregate_failures do
        expect(response).not_to be_nil
        expect(response['result']['status']).to eq('ok')
      end
    end

    it 'writes corrected content to the file' do
      before_fix = File.read(test_file)
      client.fix(file: test_file)
      after_fix = File.read(test_file)
      expect([after_fix != before_fix, after_fix.include?('@return')]).to eq([true, true])
    end
  end

  describe 'shutdown request' do
    subject(:response) { client.shutdown }

    it 'responds to shutdown request' do
      aggregate_failures do
        expect(response).not_to be_nil
        expect(response['result']['status']).to eq('shutting_down')
      end
    end

    it 'removes the socket after shutdown' do
      client.shutdown
      sleep 0.3
      expect(File.exist?(socket_path)).to be false
    end
  end

  describe 'ping request' do
    let(:ping_response) { client.ping }

    it 'responds to ping' do
      expect(ping_response).not_to be_nil
    end

    it 'returns version' do
      expect(ping_response.dig('result', 'version')).to eq(Docscribe::VERSION)
    end

    it 'returns pid' do
      expect(ping_response.dig('result', 'pid')).to eq(Process.pid)
    end

    it 'returns socket_path' do
      expect(ping_response.dig('result', 'socket_path')).to eq(socket_path)
    end

    it 'returns started_at as an ISO8601 string' do
      expect(ping_response.dig('result', 'started_at')).to be_a(String)
    end

    it 'returns uptime as an integer' do
      expect(ping_response.dig('result', 'uptime')).to be_a(Integer)
    end
  end

  describe 'idle timeout' do
    it 'stops the daemon when idle timeout expires' do
      with_idle_daemon(0.3) do |_daemon, thread|
        expect(thread.join(2)).to be(thread)
      end
    end
  end

  describe 'file cache' do
    let(:override_hash) do
      {
        'no_boilerplate' => true,
        'include' => [],
        'exclude' => [],
        'include_file' => [],
        'exclude_file' => [],
        'sig_dirs' => [],
        'rbi_dirs' => []
      }
    end

    it 'caches across repeated calls' do
      with_cache_dir do |daemon, test_file|
        orig = daemon.send(:rewrite_file, test_file, :safe)
        allow(Docscribe::InlineRewriter).to receive(:rewrite_with_report) { raise 'called twice' }
        expect(daemon.send(:rewrite_file, test_file, :safe)).to eq(orig)
      end
    end

    it 'clears cache when cli overrides change' do
      with_cache_dir do |daemon, test_file|
        daemon.send(:rewrite_file, test_file, :safe)
        daemon.send(:apply_cli_overrides, override_hash)
        expect(daemon.instance_variable_get(:@file_cache)).to be_empty
      end
    end

    it 'sets effective_config when overrides applied' do
      with_cache_dir do |daemon, _test_file|
        daemon.send(:apply_cli_overrides, override_hash)
        expect(daemon.instance_variable_get(:@effective_config)).not_to be_nil
      end
    end

    it 'records applied_overrides' do
      with_cache_dir do |daemon, _test_file|
        daemon.send(:apply_cli_overrides, override_hash)
        expect(daemon.instance_variable_get(:@applied_overrides)).to eq(override_hash)
      end
    end

    it 'unsets effective_config when overrides become nil' do
      with_cache_dir do |daemon, _test_file|
        daemon.send(:apply_cli_overrides, override_hash)
        daemon.send(:apply_cli_overrides, nil)
        expect(daemon.instance_variable_get(:@effective_config)).to be_nil
      end
    end

    it 'unsets applied_overrides when overrides become nil' do
      with_cache_dir do |daemon, _test_file|
        daemon.send(:apply_cli_overrides, override_hash)
        daemon.send(:apply_cli_overrides, nil)
        expect(daemon.instance_variable_get(:@applied_overrides)).to be_nil
      end
    end

    it 'clears cache when overrides become nil' do
      with_cache_dir do |daemon, _test_file|
        daemon.send(:apply_cli_overrides, override_hash) && daemon.send(:apply_cli_overrides, nil)
        expect(daemon.instance_variable_get(:@file_cache)).to be_empty
      end
    end
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
  describe 'rbs sig cache invalidation' do
    context 'when RBS is available' do
      before { skip_unless_rbs_available! }

      it 'invalidates cache when sig file changes without touching ruby file' do
        with_tmp_dir do |dir|
          daemon = build_sig_daemon(dir, rbs: DaemonSigHelper::DEMO_RBS_INTEGER)
          write_ruby("#{dir}/a.rb")
          r1 = rbs_rewrite(daemon, "#{dir}/a.rb")
          expect(r1).to include('@param [Integer]')
          update_sig('sig/demo.rbs', DaemonSigHelper::DEMO_RBS_STRING)
          r2 = rbs_rewrite(daemon, "#{dir}/a.rb")
          expect(r2).to include('@param [String]')
          expect(r1).not_to eq(r2)
        end
      end

      it 'invalidates cache for new file after sig change' do
        with_tmp_dir do |dir|
          daemon = build_sig_daemon(dir)
          write_ruby("#{dir}/a.rb")
          write_ruby("#{dir}/b.rb")
          r1 = rbs_rewrite(daemon, "#{dir}/a.rb")
          expect(r1).to include('@param [Integer]')
          update_sig('sig/demo.rbs', DaemonSigHelper::DEMO_RBS_STRING)
          r2 = rbs_rewrite(daemon, "#{dir}/b.rb")
          expect(r2).to include('@param [String]')
        end
      end

      it 'caches again after sig change' do
        with_tmp_dir do |dir|
          daemon = build_sig_daemon(dir)
          write_ruby("#{dir}/a.rb")
          r1 = rbs_rewrite(daemon, "#{dir}/a.rb")
          update_sig('sig/demo.rbs', DaemonSigHelper::DEMO_RBS_STRING)
          r2 = rbs_rewrite(daemon, "#{dir}/a.rb")
          allow(Docscribe::InlineRewriter).to receive(:rewrite_with_report) { raise 'should be cached' }
          r3 = rbs_rewrite(daemon, "#{dir}/a.rb")
          expect(r3).to eq(r2)
          expect(r1).not_to eq(r3)
        end
      end
    end

    context 'without RBS dependency' do
      it 'stores sig_hash in cache entry' do
        with_tmp_dir do |dir|
          prepare_sig_files('sig/a.rbs', "class A\nend\n")
          write_ruby("#{dir}/x.rb", "class A\n  def foo; end\nend\n")
          daemon = build_plain_daemon(dir)
          daemon.send(:apply_cli_overrides, rbs_overrides)
          daemon.send(:rewrite_file, "#{dir}/x.rb", :safe)
          hit = daemon.instance_variable_get(:@file_cache)[["#{dir}/x.rb", :safe]]
          expect(hit).to include(:sig_hash)
          config = daemon.instance_variable_get(:@effective_config) || daemon.instance_variable_get(:@config)
          expect(hit[:sig_hash]).to eq(daemon.send(:sig_hash_for, config))
        end
      end

      it 'sig_hash_for respects custom sig_dirs' do
        with_tmp_dir do |dir|
          prepare_sig_files('custom_sig/b.rbs', "class B\nend\n", 'sig/a.rbs', "class A\nend\n")
          daemon = build_plain_daemon(dir)
          h_custom = sig_hash_for_config(daemon, ['custom_sig'])
          h_default = sig_hash_for_config(daemon, ['sig'])
          expect(h_custom).not_to eq(h_default)
        end
      end

      it 'sig_dirs_for falls back to sig when empty' do
        with_tmp_dir do |dir|
          daemon = build_plain_daemon(dir)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => [] })
          expect(daemon.send(:sig_dirs_for, config)).to eq(['sig'])
        end
      end

      it 'sig_hash changes when new sig file added' do
        with_tmp_dir do |dir|
          prepare_sig_files('sig/a.rbs', "class A\nend\n")
          daemon = build_plain_daemon(dir)
          config = Docscribe::Config.new('rbs' => { 'enabled' => true, 'sig_dirs' => ['sig'] })
          h1 = daemon.send(:sig_hash_for, config)
          write_sig('sig/b.rbs', "class B\nend\n")
          h2 = daemon.send(:sig_hash_for, config)
          expect(h1).not_to eq(h2)
        end
      end
    end
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
end
