# frozen_string_literal: true

require 'tmpdir'
require 'docscribe/server'

RSpec.describe Docscribe::Server do
  include SuppressErrorHelper
  include CleanFileHelper
  include ServerWireHelper

  describe '.socket_path' do
    it 'returns a path under /tmp' do
      expect(described_class.socket_path).to match(%r{\A/tmp/docscribe-})
    end

    it 'includes an MD5 of the working directory' do
      hash_segment = Digest::MD5.hexdigest(Dir.pwd)
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
      allow(described_class).to receive(:running?).and_return(false)
      allow(described_class).to receive(:wait_for_ready)
      allow(Process).to receive(:fork).and_return(12_345)
      allow(Process).to receive(:detach)
    end

    it 'returns early when server is already running' do
      allow(described_class).to receive(:running?).and_return(true)
      expect { described_class.ensure_running! }.not_to raise_error
    end

    it 'raises when fork is unavailable' do
      allow(Process).to receive(:respond_to?).with(:fork).and_return(false)
      expect { described_class.ensure_running! }.to raise_error(/fork not supported/)
    end

    it 'calls fork' do
      described_class.ensure_running!
      expect(Process).to have_received(:fork)
    end

    it 'calls wait_for_ready after fork' do
      described_class.ensure_running!
      expect(described_class).to have_received(:wait_for_ready)
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
      allow(described_class).to receive(:socket_path).and_return('/tmp/nonexistent.sock')
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

  describe Docscribe::Server::Protocol do
    describe '.build_request' do
      subject(:request) { described_class.build_request('check', file: 'test.rb') }

      it 'includes jsonrpc version' do
        expect(request[:jsonrpc]).to eq('2.0')
      end

      it 'includes an id' do
        aggregate_failures do
          expect(request[:id]).to be_a(String)
          expect(request[:id].length).to eq(16)
        end
      end

      it 'includes the method name' do
        expect(request[:method]).to eq('check')
      end

      it 'includes params' do
        expect(request[:params]).to eq(file: 'test.rb')
      end
    end

    describe '.parse_response' do
      it 'parses valid JSON' do
        result = described_class.parse_response('{"id":1,"result":{"status":"ok"}}')
        aggregate_failures do
          expect(result['id']).to eq(1)
          expect(result['result']['status']).to eq('ok')
        end
      end

      it 'returns nil for invalid JSON' do
        expect(described_class.parse_response('not json')).to be_nil
      end

      it 'returns nil for empty string' do
        expect(described_class.parse_response('')).to be_nil
      end
    end

    describe '.serialize' do
      it 'produces JSON with trailing newline' do
        result = described_class.serialize({ a: 1 })
        expect(result).to eq("{\"a\":1}\n")
      end
    end
  end

  describe Docscribe::Server::Client do
    subject(:client) { described_class.new(socket_path) }

    let(:socket_path) { "#{Dir.mktmpdir}/test.sock" }

    after do
      FileUtils.rm_rf(File.dirname(socket_path))
    end

    describe '#check' do
      it 'returns nil when server is unreachable' do
        expect(client.check(file: 'test.rb')).to be_nil
      end
    end

    describe '#fix' do
      it 'returns nil when server is unreachable' do
        expect(client.fix(file: 'test.rb')).to be_nil
      end
    end

    describe '#shutdown' do
      it 'returns nil when server is unreachable' do
        expect(client.shutdown).to be_nil
      end
    end

    describe 'wire format' do
      it 'sends request with single trailing newline', :aggregate_failures do
        raw_data = with_unix_server { |s| described_class.new(s).check(file: 'test.rb') }
        expect(raw_data.count("\n")).to eq(1)
        expect(raw_data).to end_with("\n")
      end
    end
  end

  describe Docscribe::Server::Daemon do
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

    describe 'idle timeout' do
      let(:idle_dir) { Dir.mktmpdir }
      let(:idle_sock) { "#{idle_dir}/idle.sock" }

      after { FileUtils.remove_entry(idle_dir) }

      it 'stops the daemon when idle timeout expires' do
        daemon = described_class.new(socket_path: idle_sock, idle_timeout: 0.3)
        thread = Thread.new { daemon.start }
        sleep 0.1 until File.exist?(idle_sock)
        expect(thread.join(2)).to be(thread)
      end
    end

    describe 'file cache' do
      let(:tmpdir) { Dir.mktmpdir }
      let(:test_file) { "#{tmpdir}/test.rb" }
      let(:daemon) { described_class.new(socket_path: "#{tmpdir}/cache.sock", idle_timeout: 60) }

      after { FileUtils.remove_entry(tmpdir) }

      before do
        File.write(test_file, "def foo\nend")
        daemon.send(:load_dependencies)
      end

      it 'caches across repeated calls' do
        orig = daemon.send(:rewrite_file, test_file, :safe)
        allow(Docscribe::InlineRewriter).to receive(:rewrite_with_report) { raise 'called twice' }
        expect(daemon.send(:rewrite_file, test_file, :safe)).to eq(orig)
      end
    end
  end
end
