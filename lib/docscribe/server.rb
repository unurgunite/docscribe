# frozen_string_literal: true

require 'json'
require 'socket'
require 'fileutils'
require 'securerandom'
require 'digest/md5'

module Docscribe
  # Server/daemon mode for persistent multi-request operation.
  #
  # Architecture:
  # - Daemon process loads Ruby runtime once, listens on a Unix socket
  # - Client sends JSON-line requests, receives JSON-line responses
  # - Auto-shutdown after idle timeout
  # - Protocol: JSON-RPC 2.0 over Unix socket
  module Server
    SOCKET_DIR = '/tmp'
    IDLE_TIMEOUT = 300

    class << self
      # Whether a server process is listening on the socket.
      #
      # @return [Boolean]
      def running?
        return false unless File.exist?(socket_path)
        return false if File.exist?("#{socket_path}.lock")

        true
      rescue StandardError
        false
      end

      # Read the PID of the running server process.
      #
      # @return [Integer, nil]
      def read_pid
        File.read(pid_path).to_i if File.exist?(pid_path)
      rescue StandardError
        nil
      end

      # Path to the PID file for the server process.
      #
      # @return [String]
      def pid_path
        "#{socket_path}.pid"
      end

      # Derive a project-specific socket path from the current working directory.
      # Uses MD5 (deterministic across processes) instead of String#hash
      # (which varies per Ruby process due to random seeding).
      #
      # @return [String]
      def socket_path
        hash = Digest::MD5.hexdigest(Dir.pwd)
        "#{SOCKET_DIR}/docscribe-#{hash}.sock"
      end
    end

    # JSON-line protocol helpers.
    module Protocol
      module_function

      # Build a JSON-RPC request hash.
      #
      # @param [String] method method name
      # @param [Hash] params request parameters
      # @return [Hash]
      def build_request(method, params = {})
        {
          jsonrpc: '2.0',
          id: SecureRandom.hex(8),
          method: method,
          params: params
        }
      end

      # Parse a single JSON-line response.
      #
      # @param [String] line raw JSON line
      # @return [Hash, nil]
      def parse_response(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      # Serialize a hash to a JSON line.
      #
      # @param [Hash] hash
      # @return [String]
      def serialize(hash)
        "#{JSON.generate(hash)}\n"
      end
    end

    # Client for communicating with a running Docscribe daemon.
    class Client
      # @param [String, nil] socket_path custom socket path (defaults to server default)
      def initialize(socket_path = nil)
        @socket_path = socket_path || Server.socket_path
      end

      # Send a check request to the server.
      #
      # @param [String] file path to file to check
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @return [Hash, nil] response hash or nil if server unreachable
      def check(file:, strategy: :safe)
        request('check', file: file, strategy: strategy)
      end

      # Send a fix request to the server.
      #
      # @param [String] file path to file to fix
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @return [Hash, nil] response hash or nil if server unreachable
      def fix(file:, strategy: :safe)
        request('fix', file: file, strategy: strategy)
      end

      # Send a shutdown request to the server.
      #
      # @return [Hash, nil] response hash or nil if server unreachable
      def shutdown
        request('shutdown')
      end

      private

      # Send a JSON-RPC request and read the response.
      #
      # @param [String] method method name
      # @param [Hash] params request parameters
      # @return [Hash, nil]
      def request(method, **params)
        connect do |socket|
          req = Protocol.build_request(method, params)
          socket.puts(Protocol.serialize(req))
          socket.close_write
          line = socket.gets
          break unless line

          Protocol.parse_response(line)
        end
      end

      # Connect to the Unix socket and yield the connection.
      #
      # @yield [UNIXSocket]
      # @return [Object, nil] yield return value or nil on connection error
      def connect
        socket = UNIXSocket.new(@socket_path)
        yield socket
      rescue Errno::ECONNREFUSED, Errno::ENOENT
        nil
      ensure
        socket&.close
      end
    end

    # Daemon process that loads the Ruby runtime once and serves requests.
    class Daemon
      # @param [String, nil] socket_path custom socket path
      # @param [Integer] idle_timeout seconds before automatic shutdown
      def initialize(socket_path: nil, idle_timeout: IDLE_TIMEOUT)
        @socket_path = socket_path || Server.socket_path
        @idle_timeout = idle_timeout
        @last_request_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @running = false
        @server = nil
      end

      # Start the daemon: load dependencies, bind socket, enter listen loop.
      #
      # @return [void]
      def start
        load_dependencies
        setup_socket
        @running = true
        $PROGRAM_NAME = "docscribe server (#{Dir.pwd})"
        write_pid
        listen_loop
      end

      private

      # Load the full Docscribe runtime and build cached config.
      #
      # @private
      # @return [void]
      def load_dependencies
        require 'docscribe'
        @config = Docscribe::Config.load
        @config.load_plugins!
        @core_rbs_provider = @config.respond_to?(:core_rbs_provider) ? @config.core_rbs_provider : nil
      end

      # Create and bind the Unix domain socket.
      #
      # @private
      # @return [void]
      def setup_socket
        FileUtils.rm_f(@socket_path)
        FileUtils.mkdir_p(File.dirname(@socket_path))
        @server = UNIXServer.new(@socket_path)
        File.chmod(0o600, @socket_path)
      end

      # Write PID file so clients can find the server process.
      #
      # @private
      # @return [void]
      def write_pid
        File.write("#{@socket_path}.pid", Process.pid)
      end

      # Main accept loop with idle timeout check.
      #
      # @private
      # @return [void]
      def listen_loop
        while @running
          check_idle_timeout
          accept_client
          @last_request_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      rescue Interrupt
        @running = false
      ensure
        cleanup
      end

      # Check whether the idle timeout has been exceeded.
      #
      # @private
      # @return [void]
      def check_idle_timeout
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_time
        @running = false if elapsed > @idle_timeout
      end

      # Accept a client connection if one is available.
      #
      # @private
      # @return [void]
      def accept_client
        client = @server.accept if @server.wait_readable(1)
        return unless client

        handle_client(client)
      end

      # Read a request from a client connection and dispatch it.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @return [void]
      def handle_client(client)
        request_line = client.gets or return
        request = Protocol.parse_response(request_line)
        request ? handle_request(client, request) : send_error(client, nil, -32_700, 'Parse error')
      rescue StandardError => e
        send_error(client, request&.dig('id'), -32_603, "#{e.class}: #{e.message}")
      ensure
        client.close
      end

      # Dispatch a parsed request to the appropriate handler.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [Hash] request parsed JSON-RPC request
      # @return [void]
      def handle_request(client, request)
        method = request['method']
        params = request['params'] || {}

        case method
        when 'check' then handle_check(client, request['id'], params)
        when 'fix' then handle_fix(client, request['id'], params)
        when 'shutdown' then handle_shutdown(client, request['id'])
        else send_error(client, request['id'], -32_601, "Unknown method: #{method}")
        end
      end

      # Handle a check request: read file, run rewriter, return results.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [String, Integer] id request ID
      # @param [Hash] params request parameters
      # @return [void]
      def handle_check(client, id, params)
        file = params['file']
        strategy = (params['strategy'] || 'check').to_sym
        return send_error(client, id, -32_602, "File not found: #{file}") unless file && File.file?(file)

        src, result = rewrite_file(file, strategy)
        send_result(client, id, 'status' => result[:output] == src ? 'ok' : 'fail',
                                'changed' => result[:output] != src, 'changes' => result[:changes])
      end

      # Handle a fix request: read file, rewrite, write back.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [String, Integer] id request ID
      # @param [Hash] params request parameters
      # @return [void]
      def handle_fix(client, id, params)
        file = params['file']
        strategy = (params['strategy'] || 'safe').to_sym
        return send_error(client, id, -32_602, "File not found: #{file}") unless file && File.file?(file)

        src, result = rewrite_file(file, strategy)
        File.write(file, result[:output]) if result[:output] != src
        send_result(client, id, 'status' => 'ok',
                                'changed' => result[:output] != src, 'changes' => result[:changes])
      end

      # Read file, run InlineRewriter, and return [src, result].
      #
      # @private
      # @param [String] file path to file
      # @param [Symbol] strategy rewrite strategy
      # @return [Array(String, Hash)] original source and rewrite result
      def rewrite_file(file, strategy)
        src = File.read(file)
        result = Docscribe::InlineRewriter.rewrite_with_report(
          src, strategy: strategy, config: @config,
               core_rbs_provider: @core_rbs_provider, file: file
        )
        [src, result]
      end

      # Handle a shutdown request.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [String, Integer] id request ID
      # @return [void]
      def handle_shutdown(client, id)
        send_result(client, id, { 'status' => 'shutting_down' })
        @running = false
      end

      # Send a JSON-RPC result response.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [String, Integer] id request ID
      # @param [Hash] result result data
      # @return [void]
      def send_result(client, id, result)
        response = { jsonrpc: '2.0', id: id, result: result }
        client.puts(Protocol.serialize(response))
      end

      # Send a JSON-RPC error response.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [String, Integer, nil] id request ID
      # @param [Integer] code error code
      # @param [String] message error message
      # @return [void]
      def send_error(client, id, code, message)
        response = { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
        client.puts(Protocol.serialize(response))
      end

      # Cleanup socket and PID files on shutdown.
      #
      # @private
      # @return [void]
      def cleanup
        @server&.close
        File.unlink(@socket_path) if @socket_path && File.exist?(@socket_path)
        pid_path = "#{@socket_path}.pid"
        FileUtils.rm_f(pid_path)
      rescue StandardError
        nil
      end
    end
  end
end
