# frozen_string_literal: true

require 'tmpdir'
require 'docscribe/server'

RSpec.describe Docscribe::Server do
  describe '.socket_path' do
    it 'returns a path under /tmp' do
      expect(described_class.socket_path).to match(%r{\A/tmp/docscribe-})
    end

    it 'includes an MD5 of the working directory' do
      path = described_class.socket_path
      hash_segment = Digest::MD5.hexdigest(Dir.pwd)
      expect(path).to include(hash_segment)
    end
  end

  describe '.running?' do
    it 'returns false when socket does not exist' do
      allow(described_class).to receive(:socket_path).and_return('/tmp/nonexistent.sock')
      expect(described_class.running?).to be false
    end

    it 'returns false when lock file exists' do
      Dir.mktmpdir do |dir|
        sock = "#{dir}/test.sock"
        allow(described_class).to receive(:socket_path).and_return(sock)
        File.write(sock, '')
        File.write("#{sock}.lock", '')
        expect(described_class.running?).to be false
      end
    end
  end
end

RSpec.describe Docscribe::Server::Protocol do
  describe '.build_request' do
    subject(:request) { described_class.build_request('check', file: 'test.rb') }

    it 'includes jsonrpc version' do
      expect(request[:jsonrpc]).to eq('2.0')
    end

    it 'includes an id' do
      expect(request[:id]).to be_a(String)
      expect(request[:id].length).to eq(16)
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
      expect(result['id']).to eq(1)
      expect(result['result']['status']).to eq('ok')
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

RSpec.describe Docscribe::Server::Client do
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
end

RSpec.describe Docscribe::Server::Daemon do
  before do
    @tmpdir = Dir.mktmpdir
    @socket_path = "#{@tmpdir}/docscribe-test.sock"
    @test_file = "#{@tmpdir}/test.rb"

    File.write(@test_file, <<~RUBY)
      def hello
        puts 'world'
      end
    RUBY

    @daemon = described_class.new(socket_path: @socket_path, idle_timeout: 60)
    @daemon_thread = Thread.new { @daemon.start }
    sleep 0.5
  end

  after do
    c = Docscribe::Server::Client.new(@socket_path)
    begin
      c.shutdown
    rescue StandardError
      nil
    end
    @daemon_thread&.join(3)
    FileUtils.remove_entry(@tmpdir) if @tmpdir
  end

  let(:client) { Docscribe::Server::Client.new(@socket_path) }

  describe '#start' do
    it 'creates a socket file' do
      expect(File.exist?(@socket_path)).to be true
    end

    it 'creates a PID file' do
      expect(File.exist?("#{@socket_path}.pid")).to be true
    end
  end

  describe 'check request' do
    it 'returns ok for a file with no issues' do
      clean_file = "#{@tmpdir}/clean.rb"
      File.write(clean_file, <<~RUBY)
        # Documented method
        # @return [String]
        def greet
          'hello'
        end
      RUBY

      response = client.check(file: clean_file)
      expect(response).not_to be_nil
      expect(response['result']['status']).to eq('ok')
      expect(response['result']['changed']).to be false
    end

    it 'returns fail for a file needing updates' do
      response = client.check(file: @test_file)
      expect(response).not_to be_nil
      expect(response['result']['status']).to eq('fail')
      expect(response['result']['changed']).to be true
      expect(response['result']['changes']).to be_an(Array)
      expect(response['result']['changes']).not_to be_empty
    end

    it 'returns error for a nonexistent file' do
      response = client.check(file: '/nonexistent.rb')
      expect(response).not_to be_nil
      expect(response['error']).not_to be_nil
      expect(response['error']['message']).to include('File not found')
    end
  end

  describe 'fix request' do
    it 'writes corrected content to the file' do
      original = File.read(@test_file)
      response = client.fix(file: @test_file)
      expect(response).not_to be_nil
      expect(response['result']['status']).to eq('ok')

      updated = File.read(@test_file)
      expect(updated).not_to eq(original)
      expect(updated).to include('@return')
    end
  end

  describe 'shutdown request' do
    it 'stops the daemon' do
      expect(File.exist?(@socket_path)).to be true

      response = client.shutdown
      expect(response).not_to be_nil
      expect(response['result']['status']).to eq('shutting_down')

      sleep 0.3
      expect(File.exist?(@socket_path)).to be false
    end
  end
end
