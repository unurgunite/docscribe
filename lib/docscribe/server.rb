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
      # Start the server daemon and wait for it to become ready.
      #
      # @param [String?] config_path optional config path for socket/pid lookup
      # @param [Boolean] daemonize redirect stdin/stdout/stderr to /dev/null
      # @param [Integer] timeout max seconds to wait for readiness
      # @raise [StandardError]
      # @return [void]
      def ensure_running!(config_path: nil, daemonize: false, timeout: 5)
        return if running?(config_path)
        raise 'Server mode is unavailable on this Ruby/platform (Process.fork not supported)' unless Process.respond_to?(:fork)

        warn 'Docscribe: starting server...'
        pid = Process.fork do # steep:ignore NoMethod
          [$stdin, $stdout].each { _1.reopen(File::NULL) }
          $stderr.reopen(File::NULL) if daemonize
          Daemon.new(config_path: config_path).start
        end
        Process.detach(pid)
        wait_for_ready(config_path: config_path, timeout: timeout)
      end

      # Wait for the server to accept connections.
      #
      # @param [String?] config_path optional config path for socket/pid lookup
      # @param [Integer] timeout max seconds to wait
      # @param [Boolean] raise_on_timeout raise vs warn on timeout
      # @raise [StandardError]
      # @return [void]
      def wait_for_ready(config_path: nil, timeout: 5, raise_on_timeout: true)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return if running?(config_path)

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise('Docscribe: server failed to start') if raise_on_timeout

            warn('Docscribe server failed to start within timeout')
            return
          end

          sleep 0.1
        end
      end

      # Whether a server process is listening on the socket.
      #
      # On ECONNREFUSED, checks whether the PID process is still alive:
      # if yes, the daemon is still starting up (don't clean up);
      # if no, removes stale socket and pid files.
      #
      # @param [String?] config_path optional config path for socket lookup
      # @raise [Errno::ECONNREFUSED]
      # @raise [Errno::ENOENT]
      # @raise [Errno::ENOTSOCK]
      # @raise [StandardError]
      # @return [Boolean]
      # @return [Boolean] if Errno::ECONNREFUSED
      # @return [Boolean] if Errno::ENOENT, Errno::ENOTSOCK
      # @return [Boolean] if StandardError
      def running?(config_path = nil)
        socket = UNIXSocket.new(socket_path(config_path))
        socket.close
        true
      rescue Errno::ECONNREFUSED
        handle_stale_socket?(config_path)
      rescue Errno::ENOENT, Errno::ENOTSOCK
        clean_socket_files(config_path)
        false
      rescue StandardError
        false
      end

      private

      # Handle ECONNREFUSED: check if the pid process is alive.
      # Cleans up only if the process is dead.
      #
      # @private
      # @param [String?] config_path
      # @return [Boolean] false (not running)
      def handle_stale_socket?(config_path)
        pid = read_pid(config_path)
        return false if pid && process_alive?(pid)

        clean_socket_files(config_path)
        false
      end

      # @private
      # @param [Integer] pid
      # @raise [Errno::ESRCH]
      # @return [Boolean]
      # @return [Boolean] if Errno::ESRCH
      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end

      # @param [String?] config_path
      # @raise [StandardError]
      # @return [Integer?]
      # @return [nil] if StandardError
      def read_pid(config_path = nil)
        File.read(pid_path(config_path)).to_i if File.exist?(pid_path(config_path))
      rescue StandardError
        nil
      end

      # Remove stale socket and pid files.
      # @private
      # @param [String?] config_path
      # @return [void]
      def clean_socket_files(config_path)
        FileUtils.rm_f(socket_path(config_path))
        FileUtils.rm_f(pid_path(config_path))
      end

      # @param [String?] config_path
      # @return [String]
      def pid_path(config_path = nil)
        "#{socket_path(config_path)}.pid"
      end

      # Derive a project-specific socket path from the current working directory.
      # Uses MD5 (deterministic across processes) instead of String#hash
      # (which varies per Ruby process due to random seeding).
      # When a config_path is given, its path + mtime are included in the hash
      # so different configs get different daemons.
      #
      # @param [String?] config_path optional config path to differentiate
      # @return [String]
      def socket_path(config_path = nil)
        hash = Digest::MD5.hexdigest(Dir.pwd)
        if config_path
          resolved = File.expand_path(config_path)
          mtime = File.exist?(resolved) ? File.mtime(resolved).to_f : 0.0
          cfg_hash = Digest::MD5.hexdigest("#{resolved}:#{mtime}")
          "#{SOCKET_DIR}/docscribe-#{hash}-#{cfg_hash}.sock"
        else
          "#{SOCKET_DIR}/docscribe-#{hash}.sock"
        end
      end

      public :read_pid
      public :pid_path
      public :socket_path
    end

    # JSON-line protocol helpers.
    module Protocol
      module_function

      # Build a JSON-RPC request hash.
      #
      # @note module_function: defines #build_request (visibility: private)
      # @param [String] method method name
      # @param [Hash<Symbol, Object>] params request parameters
      # @return [Hash<Symbol, Object>]
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
      # @note module_function: defines #parse_response (visibility: private)
      # @param [String] line raw JSON line
      # @raise [JSON::ParserError]
      # @return [Hash<String, Object>?] if JSON::ParserError
      # @return [nil] if JSON::ParserError
      def parse_response(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      # Serialize a hash to a JSON line.
      #
      # @note module_function: defines #serialize (visibility: private)
      # @param [Hash<Object, Object>] hash
      # @return [String]
      def serialize(hash)
        "#{JSON.generate(hash)}\n"
      end
    end

    # Client for communicating with a running Docscribe daemon.
    class Client
      # @param [nil] socket_path custom socket path (defaults to server default)
      # @param [nil] config_path optional config path for socket lookup
      # @return [Object]
      def initialize(socket_path = nil, config_path: nil)
        @socket_path = socket_path || Server.socket_path(config_path)
      end

      # Send a check request to the server.
      #
      # @param [Object] file path to file to check
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @return [Object] response hash or nil if server unreachable
      def check(file:, strategy: :safe)
        request('check', file: file, strategy: strategy)
      end

      # Send a fix request to the server.
      #
      # @param [Object] file path to file to fix
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @return [Object] response hash or nil if server unreachable
      def fix(file:, strategy: :safe)
        request('fix', file: file, strategy: strategy)
      end

      # Send a shutdown request to the server.
      #
      # @return [Object] response hash or nil if server unreachable
      def shutdown
        request('shutdown')
      end

      private

      # Send a JSON-RPC request and read the response.
      #
      # @private
      # @param [Object] method method name
      # @param [Hash] params request parameters
      # @return [Object]
      def request(method, **params)
        connect do |socket|
          req = Protocol.build_request(method, params)
          socket.write(Protocol.serialize(req))
          socket.close_write
          line = socket.gets
          break unless line

          Protocol.parse_response(line)
        end
      end

      # Connect to the Unix socket and yield the connection.
      #
      # @private
      # @raise [Errno::ECONNREFUSED]
      # @raise [Errno::ENOENT]
      # @return [Object?, Object] yield return value or nil on connection error
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
      # @param [nil] socket_path custom socket path
      # @param [IDLE_TIMEOUT] idle_timeout seconds before automatic shutdown
      # @param [nil] config_path custom config path
      # @return [nil]
      def initialize(socket_path: nil, idle_timeout: IDLE_TIMEOUT, config_path: nil)
        @socket_path = socket_path || Server.socket_path(config_path)
        @idle_timeout = idle_timeout
        @config_path = config_path
        @last_request_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @running = false
        @server = nil
      end

      # Start the daemon: load dependencies, bind socket, enter listen loop.
      #
      # @return [Object]
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
      # @return [Object]
      def load_dependencies
        require 'docscribe'
        @config = Docscribe::Config.load(@config_path)
        @config&.load_plugins!
        @core_rbs_provider = @config&.core_rbs_provider
      end

      # Create and bind the Unix domain socket.
      #
      # @private
      # @return [Object]
      def setup_socket
        FileUtils.rm_f(@socket_path)
        FileUtils.mkdir_p(File.dirname(@socket_path))
        @server = UNIXServer.new(@socket_path)
        File.chmod(0o600, @socket_path)
      end

      # Write PID file so clients can find the server process.
      #
      # @private
      # @return [Object]
      def write_pid
        File.write("#{@socket_path}.pid", Process.pid)
      end

      # Main accept loop with idle timeout check.
      #
      # @private
      # @raise [Interrupt]
      # @return [Object, Boolean, Object]
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
      # @return [Boolean?]
      def check_idle_timeout
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_time
        @running = false if elapsed > @idle_timeout
      end

      # Accept a client connection if one is available.
      #
      # @private
      # @return [Object]
      def accept_client
        client = @server&.accept if @server&.wait_readable(1)
        return unless client

        handle_client(client)
      end

      # Read a request from a client connection and dispatch it.
      #
      # @private
      # @param [Object] client connected client socket
      # @raise [StandardError]
      # @return [Object]
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
      # @param [Object] client connected client socket
      # @param [Object] request parsed JSON-RPC request
      # @return [Object]
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
      # @param [Object] client connected client socket
      # @param [Object] id request ID
      # @param [Object] params request parameters
      # @return [Object]
      def handle_check(client, id, params)
        file = params['file']
        strategy = (params['strategy'] || 'safe').to_sym
        return send_error(client, id, -32_602, "File not found: #{file}") unless file && File.file?(file)

        src, result = rewrite_file(file, strategy)
        send_result(client, id, 'status' => result[:output] == src ? 'ok' : 'fail',
                                'changed' => result[:output] != src, 'changes' => result[:changes])
      end

      # Handle a fix request: read file, rewrite, write back.
      #
      # @private
      # @param [Object] client connected client socket
      # @param [Object] id request ID
      # @param [Object] params request parameters
      # @return [Object]
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
      # @param [Object] file path to file
      # @param [Object] strategy rewrite strategy
      # @return [Array] original source and rewrite result
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
      # @param [Object] client connected client socket
      # @param [Object] id request ID
      # @return [Boolean]
      def handle_shutdown(client, id)
        send_result(client, id, { 'status' => 'shutting_down' })
        @running = false
      end

      # Send a JSON-RPC result response.
      #
      # @private
      # @param [Object] client connected client socket
      # @param [Object] id request ID
      # @param [Object] result result data
      # @return [nil]
      def send_result(client, id, result)
        response = { jsonrpc: '2.0', id: id, result: result }
        client.puts(Protocol.serialize(response))
      end

      # Send a JSON-RPC error response.
      #
      # @private
      # @param [Object] client connected client socket
      # @param [Object] id request ID
      # @param [Object] code error code
      # @param [Object] message error message
      # @return [nil]
      def send_error(client, id, code, message)
        response = { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
        client.puts(Protocol.serialize(response))
      end

      # Cleanup socket and PID files on shutdown.
      #
      # @private
      # @raise [StandardError]
      # @return [Object] if StandardError
      # @return [nil] if StandardError
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
