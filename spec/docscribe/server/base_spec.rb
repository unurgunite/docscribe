# frozen_string_literal: true

require 'tmpdir'
require 'docscribe/server'

RSpec.describe Docscribe::Server do
  describe '.socket_path' do
    it 'returns a path under tmpdir' do
      expect(described_class.socket_path).to match(%r{\A(?:#{Regexp.escape(Dir.tmpdir)}|/tmp)/docscribe-})
    end

    it 'includes an MD5 of the working directory' do
      seed = +Dir.pwd
      seed << ":#{described_class.send(:env_hash)}"
      hash_segment = Digest::MD5.hexdigest(seed)
      expect(described_class.socket_path).to include(hash_segment)
    end

    describe 'with config_path' do
      around { |ex| Dir.mktmpdir { |t| Dir.chdir(t, &ex) } }

      it 'resolves relative path to absolute before hashing' do
        rel = described_class.socket_path('some.yml')
        abs = described_class.socket_path("#{Dir.pwd}/some.yml")
        expect(rel).to eq(abs)
      end

      it 'includes mtime as float' do
        File.write('cfg.yml', '')
        expect(described_class.socket_path('cfg.yml')).to match(/\.sock\z/)
      end
    end
  end

  describe '.wait_for_ready' do
    it 'returns when server becomes ready' do
      allow(described_class).to receive(:running?).and_return(true)
      expect { described_class.wait_for_ready(timeout: 5) }.not_to raise_error
    end

    it 'raises on timeout when raise_on_timeout is true' do
      allow(described_class).to receive(:running?).and_return(false)

      expect do
        described_class.wait_for_ready(timeout: 0.01, raise_on_timeout: true)
      end.to raise_error(RuntimeError, 'Docscribe: server failed to start')
    end

    it 'does not raise on timeout when raise_on_timeout is false' do
      allow(described_class).to receive(:running?).and_return(false)

      expect do
        described_class.wait_for_ready(timeout: 0.01, raise_on_timeout: false)
      end.not_to raise_error
    end
  end

  describe '.process_alive?' do
    it 'returns true when process exists' do
      expect(described_class.send(:process_alive?, Process.pid)).to be true
    end

    it 'returns false when process is gone' do
      pid = spawn('true')
      Process.wait(pid)
      expect(described_class.send(:process_alive?, pid)).to be false
    end
  end

  describe '.ensure_running!' do
    before do
      allow(described_class).to receive_messages(running?: false, wait_for_ready: false)
      allow(Process).to receive(:fork).and_return(12_345)
      allow(Process).to receive(:detach)
    end

    it 'returns early when server is already running' do
      allow(described_class).to receive(:running?).and_return(true)
      described_class.ensure_running!
      expect(Process).not_to have_received(:fork)
    end

    it 'raises when fork is unavailable' do
      allow(Process).to receive(:respond_to?).with(:fork).and_return(false)
      expect { described_class.ensure_running! }.to raise_error(/JRuby/)
    end

    it 'calls fork' do
      described_class.ensure_running!
      expect(Process).to have_received(:fork)
    end

    it 'calls wait_for_ready after fork' do
      described_class.ensure_running!
      expect(described_class).to have_received(:wait_for_ready).at_least(:once)
    end
  end

  describe '.handle_stale_socket?' do
    let(:dir) { Dir.mktmpdir }
    let(:sock) { "#{dir}/test.sock" }
    let(:pidfile) { "#{dir}/test.pid" }
    let(:setup_alive) do
      allow(described_class).to receive(:read_pid).and_return(Process.pid)
      allow(described_class).to receive_messages(socket_path: sock, pid_path: pidfile)
      File.write(sock, '')
    end
    let(:setup_dead) do
      pid = spawn('true')
      Process.wait(pid)
      allow(described_class).to receive(:read_pid).and_return(pid)
      allow(described_class).to receive_messages(socket_path: sock, pid_path: pidfile)
      pid
    end

    after { FileUtils.rm_rf(dir) }

    it 'returns false when PID is alive' do
      setup_alive
      expect(described_class.send(:handle_stale_socket?, nil)).to be false
    end

    it 'does not clean up socket when PID is alive' do
      setup_alive
      described_class.send(:handle_stale_socket?, nil)
      expect(File.exist?(sock)).to be true
    end

    it 'cleans up socket when PID is dead' do
      _pid = setup_dead
      File.write(sock, '')
      described_class.send(:handle_stale_socket?, nil)
      expect(File.exist?(sock)).to be false
    end

    it 'cleans up pidfile when PID is dead' do
      pid = setup_dead
      File.write(pidfile, pid.to_s)
      described_class.send(:handle_stale_socket?, nil)
      expect(File.exist?(pidfile)).to be false
    end
  end

  describe '.running?' do
    let(:dir) { Dir.mktmpdir }
    let(:sock) { "#{dir}/test.sock" }

    after { FileUtils.rm_rf(dir) }

    it 'returns false when socket does not exist' do
      allow(described_class).to receive(:socket_path).and_return("#{Dir.tmpdir}/nonexistent.sock")
      expect(described_class.running?).to be false
    end

    it 'returns false when socket file is stale (not a real socket)' do
      allow(described_class).to receive_messages(socket_path: sock, pid_path: "#{dir}/test.pid")
      File.write(sock, '')
      expect(described_class.running?).to be false
    end

    it 'cleans up stale socket file' do
      allow(described_class).to receive_messages(socket_path: sock, pid_path: "#{dir}/test.pid")
      File.write(sock, '')
      described_class.running?
      expect(File.exist?(sock)).to be false
    end
  end
end
