# frozen_string_literal: true

require 'docscribe/server'
require 'fileutils'
require 'tmpdir'

RSpec.describe Docscribe::Server::Daemon do
  include SuppressErrorHelper
  include CleanFileHelper

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
    it 'returns ok for a file with no issues' do
      response = client.check(file: create_clean_file(socket_path))
      aggregate_failures do
        expect(response).not_to be_nil
        expect(response['result'].slice('status', 'changed')).to eq('status' => 'ok', 'changed' => false)
      end
    end

    it 'returns fail for a file needing updates' do
      response = client.check(file: test_file)
      aggregate_failures do
        expect(response).not_to be_nil
        expect(response['result']['status']).to eq('fail')
      end
    end

    it 'returns error for a nonexistent file' do
      response = client.check(file: '/nonexistent.rb')
      aggregate_failures do
        expect(response).not_to be_nil
        expect(response.dig('error', 'message')).to include('File not found')
      end
    end

    it 'defaults to safe strategy when not specified', :aggregate_failures do
      response = client.check(file: test_file)
      expect(response).not_to be_nil
      expect(response['error']).to be_nil
      expect(response['result']).to have_key('status')
    end
  end

  describe 'fix request' do
    it 'returns success status' do
      response = client.fix(file: test_file)
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
    it 'responds to shutdown request' do
      response = client.shutdown
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
    def ping_response
      client.ping
    end

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
    def with_idle_daemon(timeout)
      Dir.mktmpdir do |dir|
        sock = "#{dir}/idle.sock"
        daemon = described_class.new(socket_path: sock, idle_timeout: timeout)
        thread = Thread.new { daemon.start }
        sleep 0.1 until File.exist?(sock)
        yield daemon, thread
      end
    end

    it 'stops the daemon when idle timeout expires' do
      with_idle_daemon(0.3) do |_daemon, thread|
        expect(thread.join(2)).to be(thread)
      end
    end
  end

  describe 'file cache' do
    def with_cache_dir
      Dir.mktmpdir do |dir|
        test_file = "#{dir}/test.rb"
        daemon = described_class.new(socket_path: "#{dir}/cache.sock", idle_timeout: 60)
        File.write(test_file, "def foo\nend")
        daemon.send(:load_dependencies)
        yield daemon, test_file
      end
    end

    def override_hash
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
end
