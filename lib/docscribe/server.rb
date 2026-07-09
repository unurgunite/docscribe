# frozen_string_literal: true

require 'json'
require 'socket'
require 'fileutils'
require 'securerandom'
require 'digest/md5'
require 'tmpdir'
require 'time'
require_relative 'lru_cache'

module Docscribe
  # Server/daemon mode for persistent multi-request operation.
  #
  # Architecture:
  # - Daemon process loads Ruby runtime once, listens on a Unix socket
  # - Client sends JSON-line requests, receives JSON-line responses
  # - Auto-shutdown after idle timeout
  # - Protocol: JSON-RPC 2.0 over Unix socket
  module Server
    # Unix socket path max is 104 bytes on macOS (the more restrictive).
    # Dir.tmpdir on macOS often returns a long path under /var/folders/.../T
    # that exceeds this limit, so we fall back to /tmp when needed.
    SOCKET_DIR = begin
      tmp = Dir.tmpdir || '/tmp'
      sock_overhead = "/docscribe-#{'a' * 32}.sock".bytesize # 48
      tmp.bytesize <= 104 - sock_overhead ? tmp : '/tmp'
    end
    IDLE_TIMEOUT = 300

    class << self
      # Start the server daemon if not running.
      #
      # @param [String?] config_path optional config file path
      # @param [Boolean] daemonize redirect stdin/stdout/stderr to /dev/null
      # @param [Integer] timeout max seconds to wait for readiness
      # @return [void]
      def ensure_running!(config_path: nil, daemonize: false, timeout: 5)
        return if running?(config_path)

        check_platform_support!

        lock_path = "#{socket_path(config_path)}.lock"
        File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          next if running?(config_path)

          start_daemon_process(config_path: config_path, daemonize: daemonize)
        end
        wait_for_ready(config_path: config_path, timeout: timeout)
      end

      # Start the server daemon and wait for it to become ready.
      #
      # @param [String?] config_path optional config path for socket/pid lookup
      # @param [Integer] timeout max seconds to wait for readiness
      # @param [Boolean] raise_on_timeout
      # @raise [StandardError]
      # @return [Boolean]
      def wait_for_ready(config_path: nil, timeout: 5, raise_on_timeout: true) # rubocop:disable SortedMethodsByCall/Waterfall
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return true if running?(config_path)

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise('Docscribe: server failed to start') if raise_on_timeout

            warn('Docscribe server failed to start within timeout')
            return false
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
      # @return [void, Boolean] if Errno::ENOENT, Errno::ENOTSOCK
      # @return [Boolean] if StandardError
      def running?(config_path = nil)
        return false unless defined?(UNIXSocket)

        socket = UNIXSocket.new(socket_path(config_path))
        socket.close
        true
      rescue Errno::ECONNREFUSED
        handle_stale_socket?(config_path)
      rescue Errno::ENOENT, Errno::ENOTSOCK
        clean_socket_files(config_path) || false
      rescue StandardError
        false
      end

      # Handle ECONNREFUSED: check if the pid process is alive.
      # Cleans up only if the process is dead.
      #
      # @param [String?] config_path
      # @return [Boolean] false (not running)
      def handle_stale_socket?(config_path)
        pid = read_pid(config_path)
        return false if pid && process_alive?(pid)

        clean_socket_files(config_path)
        false
      end

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
      #
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

      ENV_FILES = %w[Gemfile.lock rbs_collection.lock.yaml].freeze

      # @param [String] config_path
      # @return [String]
      def config_hash(config_path)
        resolved = File.expand_path(config_path)
        mtime = File.exist?(resolved) ? File.mtime(resolved).to_f : 0.0
        Digest::MD5.hexdigest("#{resolved}:#{mtime}")
      end

      # Check platform compatibility before starting server.
      #
      # @raise [StandardError]
      # @return [void]
      def check_platform_support!
        unless defined?(UNIXSocket)
          raise 'Server mode requires Unix domain sockets, which are not available on Windows. ' \
                'Use docscribe directly without --server flag.'
        end
        return if Process.respond_to?(:fork)

        raise 'Server mode requires Process.fork, which is not available on JRuby. ' \
              'Use docscribe directly without --server flag.'
      end

      # Derive a project-specific socket path from the current working directory.
      # Uses MD5 (deterministic across processes) instead of String#hash
      # (which varies per Ruby process due to random seeding).
      # When a config_path is given, its path + mtime are included in the hash
      # so different configs get different daemons.
      # Environment files (Gemfile.lock, rbs_collection.lock.yaml) are also
      # included so daemon is invalidated when gems or RBS types change.
      #
      # @param [String?] config_path optional config path to differentiate
      # @return [String]
      def socket_path(config_path = nil)
        seed = +Dir.pwd
        seed << ":#{env_hash}"
        if config_path
          resolved = File.expand_path(config_path)
          mtime = File.exist?(resolved) ? File.mtime(resolved).to_f : 0.0
          seed << ":#{resolved}:#{mtime}"
        end
        "#{SOCKET_DIR}/docscribe-#{Digest::MD5.hexdigest(seed)}.sock"
      end

      # Hash of environment files that affect analysis results.
      # When any of these change, the daemon is invalidated (new socket path).
      #
      # @return [String]
      def env_hash
        parts = ENV_FILES.map do |file|
          path = File.join(Dir.pwd, file)
          File.exist?(path) ? File.mtime(path).to_f.to_s : '0'
        end
        Digest::MD5.hexdigest(parts.join(':'))
      end

      public :read_pid, :pid_path, :socket_path

      # @param [String?] config_path
      # @param [Boolean] daemonize
      # @return [void]
      def start_daemon_process(config_path:, daemonize:)
        warn 'Docscribe: starting server...' if daemonize
        pid = Process.fork do # steep:ignore NoMethod
          [$stdin, $stdout].each { _1.reopen(File::NULL) }
          $stderr.reopen(File::NULL)
          Daemon.new(config_path: config_path).start
        end
        Process.detach(pid)
      end
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
      # @return [Hash<String, Object>?]
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
      # @param [String?] socket_path custom socket path (defaults to server default)
      # @param [String?] config_path optional config path for socket lookup
      # @return [void]
      def initialize(socket_path = nil, config_path: nil)
        @socket_path = socket_path || Server.socket_path(config_path)
      end

      # Send a check request to the server.
      #
      # @param [String] file path to file to check
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @param [Object] rest
      # @return [Hash<String, Object>?] response hash or nil if server unreachable
      def check(file:, strategy: :safe, **rest)
        request('check', file: file, strategy: strategy, **rest)
      end

      # Send a fix request to the server.
      #
      # @param [String] file path to file to fix
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @param [Object] rest
      # @return [Hash<String, Object>?] response hash or nil if server unreachable
      def fix(file:, strategy: :safe, **rest)
        request('fix', file: file, strategy: strategy, **rest)
      end

      # Send a shutdown request to the server.
      #
      # @return [Hash<String, Object>?] response hash or nil if server unreachable
      def shutdown
        request('shutdown')
      end

      # Ping the server and get version/pid/uptime info.
      #
      # @return [Hash<String, Object>?] response hash or nil if server unreachable
      def ping
        request('ping')
      end

      private

      # Send a JSON-RPC request and read the response.
      #
      # @private
      # @param [String] method method name
      # @param [Object] params request parameters
      # @return [Hash<String, Object>?]
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
      # @return [T?] yield return value or nil on connection error
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
      # Standardized JSON-RPC error codes.
      ERROR_CODES = {
        gem_not_found: -32_000,
        syntax_error: -32_001,
        config_load_failure: -32_002,
        timeout: -32_010,
        internal: -32_099
      }.freeze
      # @param [String?] socket_path custom socket path
      # @param [Integer] idle_timeout seconds before automatic shutdown
      # @param [String?] config_path custom config path
      # @return [void]
      def initialize(socket_path: nil, idle_timeout: IDLE_TIMEOUT, config_path: nil)
        @socket_path = socket_path || Server.socket_path(config_path)
        @idle_timeout = idle_timeout
        @config_path = config_path
        @last_request_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @running = false
        @server = nil
        @file_cache = LRUCache.new
        @started_at = Time.now
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
        @config = Docscribe::Config.load(@config_path)
        @config&.load_plugins!
        @core_rbs_provider = @config&.core_rbs_provider
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

      # @private
      # @return [void]
      def write_pid
        File.write("#{@socket_path}.pid", Process.pid)
      end

      # Main accept loop with idle timeout check.
      #
      # @private
      # @raise [Interrupt]
      # @return [void]
      def listen_loop
        while @running
          check_idle_timeout
          accept_client
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
        client = @server&.accept if @server&.wait_readable(1)
        return unless client

        handle_client(client)
        @last_request_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Read a request from a client connection and dispatch it.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @raise [StandardError]
      # @return [void]
      def handle_client(client)
        request_line = client.gets or return
        request = Protocol.parse_response(request_line)
        request ? handle_request(client, request) : send_error(client, nil, -32_700, 'Parse error')
      rescue StandardError => e
        method_name = request&.dig('method')
        error_params = request&.dig('params') || {}
        code, message, data = classify_error(e, method_name, error_params)
        send_error(client, request&.dig('id'), code, message, data)
      ensure
        client.close
      end

      # Dispatch a parsed request to the appropriate handler.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [Hash<String, Object>] request parsed JSON-RPC request
      # @return [void]
      def handle_request(client, request)
        method = request['method']
        params = request['params'] || {}

        case method
        when 'check' then handle_check(client, request['id'], params)
        when 'fix' then handle_fix(client, request['id'], params)
        when 'shutdown' then handle_shutdown(client, request['id'])
        when 'ping' then handle_ping(client, request['id'])
        else send_error(client, request['id'], -32_601, "Unknown method: #{method}")
        end
      end

      # @private
      # @param [UNIXSocket] client
      # @param [String, Integer] id
      # @param [Hash<String, Object>] params
      # @raise [StandardError]
      # @return [void]
      # @return [void] if StandardError
      def handle_check(client, id, params)
        file = params['file']
        strategy = (params['strategy'] || 'safe').to_sym
        return send_error(client, id, -32_602, "File not found: #{file}") unless file && File.file?(file)

        apply_cli_overrides(params['cli_overrides'])
        src, result = rewrite_file(file, strategy)
        send_result(client, id, 'status' => result[:output] == src ? 'ok' : 'fail',
                                'changed' => result[:output] != src, 'changes' => result[:changes])
      rescue StandardError => e
        handle_request_error(client, id, e, file)
      end

      # @private
      # @param [UNIXSocket] client
      # @param [String, Integer] id
      # @param [Hash<String, Object>] params
      # @raise [StandardError]
      # @return [void]
      # @return [void] if StandardError
      def handle_fix(client, id, params)
        file = params['file']
        strategy = (params['strategy'] || 'safe').to_sym
        return send_error(client, id, -32_602, "File not found: #{file}") unless file && File.file?(file)

        apply_cli_overrides(params['cli_overrides'])
        src, result = rewrite_file(file, strategy)
        changed = result[:output] != src
        File.write(file, result[:output]) if changed
        send_result(client, id, 'status' => 'ok', 'changed' => changed, 'changes' => result[:changes])
      rescue StandardError => e
        handle_request_error(client, id, e, file)
      end

      # @private
      # @param [Hash<String, Object>?] overrides
      # @return [void]
      def apply_cli_overrides(overrides)
        return reset_effective_config if overrides.nil? || overrides.empty?
        return if @applied_overrides == overrides

        config = @config or return
        require 'docscribe/cli/config_builder'
        opts = overrides.transform_keys(&:to_sym)
        @effective_config = Docscribe::CLI::ConfigBuilder.build(config, opts)
        @file_cache.clear
        @applied_overrides = overrides
      end

      # @private
      # @return [void]
      def reset_effective_config
        return unless @effective_config

        @effective_config = nil
        @applied_overrides = nil
        @file_cache.clear
      end

      # @private
      # @param [String] file
      # @param [Symbol] strategy
      # @raise [StandardError]
      # @return [(String, Hash<Symbol, Object>)]
      def rewrite_file(file, strategy)
        config = @effective_config || @config or raise 'Docscribe: config not loaded'
        key = [file, strategy]
        mtime = File.mtime(file)
        hit = @file_cache[key]
        return [hit[:src], hit[:result]] if hit && hit[:mtime] == mtime

        src = File.read(file)
        rbs = config.respond_to?(:core_rbs_provider) ? config.core_rbs_provider : nil
        result = Docscribe::InlineRewriter.rewrite_with_report(src, strategy: strategy, config: config, core_rbs_provider: rbs, file: file)
        @file_cache[key] = { mtime: mtime, src: src, result: result }
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

      # Handle a ping request.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [String, Integer] id request ID
      # @return [void]
      def handle_ping(client, id)
        uptime = (Time.now - @started_at).to_i
        send_result(client, id, {
                      'version' => Docscribe::VERSION,
                      'pid' => Process.pid,
                      'socket_path' => @socket_path,
                      'started_at' => @started_at.iso8601,
                      'uptime' => uptime
                    })
      end

      # Send a JSON-RPC result response.
      #
      # @private
      # @param [UNIXSocket] client connected client socket
      # @param [String, Integer] id request ID
      # @param [Hash<String, Object>] result result data
      # @return [void]
      def send_result(client, id, result)
        response = { jsonrpc: '2.0', id: id, result: result }
        client.write(Protocol.serialize(response))
      end

      # @private
      # @param [Exception] exception
      # @param [String?] _method_name
      # @param [Hash<String, Object>] params
      # @return [(Integer, String, Object?)]
      def classify_error(exception, _method_name = nil, params = {})
        if exception.is_a?(LoadError) || exception.is_a?(Gem::LoadError)
          classify_gem_error(exception)
        elsif syntax_error?(exception)
          classify_syntax_err(exception, params)
        elsif timeout_error?(exception)
          classify_timeout_err(exception, params)
        else
          classify_internal_err(exception)
        end
      end

      # @private
      # @param [Exception] exception
      # @return [Boolean]
      def syntax_error?(exception)
        exception.is_a?(Docscribe::ParseError) ||
          (defined?(Parser::SyntaxError) && exception.is_a?(Parser::SyntaxError))
      end

      # @private
      # @param [Exception] exception
      # @return [Boolean]
      def timeout_error?(exception)
        !!defined?(Timeout::Error) && exception.is_a?(Timeout::Error)
      end

      # @private
      # @param [Object] exception
      # @return [(Integer, String, Object)]
      def classify_gem_error(exception)
        data = { gem: nil }
        data[:gem] = exception.path if exception.respond_to?(:path) && exception.path
        [ERROR_CODES[:gem_not_found], "#{exception.class}: #{exception.message}", data]
      end

      # @private
      # @param [Object] exception
      # @param [Hash<String, Object>] params
      # @return [(Integer, String, Object)]
      def classify_syntax_err(exception, params)
        file = (params['file'] if params.is_a?(Hash)).to_s
        line = if exception.respond_to?(:line)
                 exception.line
               elsif exception.respond_to?(:diagnostic)
                 exception.diagnostic.location.line
               end
        data = { file: file, detail: exception.message, line: line }.compact
        [ERROR_CODES[:syntax_error], "Syntax error in #{file}", data]
      end

      # @private
      # @param [Object] exception
      # @param [Hash<String, Object>] params
      # @return [(Integer, String, Object)]
      def classify_timeout_err(exception, params)
        file = (params['file'] if params.is_a?(Hash)).to_s
        data = { timeout: @idle_timeout || 30, file: file }
        [ERROR_CODES[:timeout], "#{exception.class}: #{exception.message}", data]
      end

      # @private
      # @param [Object] exception
      # @return [(Integer, String, Object)]
      def classify_internal_err(exception)
        backtrace = exception.backtrace&.first(5) || []
        data = { backtrace: backtrace }
        [ERROR_CODES[:internal], "#{exception.class}: #{exception.message}", data]
      end

      # @private
      # @param [UNIXSocket] client
      # @param [String, Integer] id
      # @param [Object] exception
      # @param [String] file
      # @raise [StandardError]
      # @return [void]
      def handle_request_error(client, id, exception, file)
        if exception.is_a?(Docscribe::ParseError) ||
           (defined?(Parser::SyntaxError) && exception.is_a?(Parser::SyntaxError))
          send_syntax_error(client, id, exception, file)
        else
          raise
        end
      end

      # @private
      # @param [UNIXSocket] client
      # @param [String, Integer] id
      # @param [Object] exception
      # @param [String] file
      # @return [void]
      def send_syntax_error(client, id, exception, file)
        line = if exception.respond_to?(:line)
                 exception.line
               elsif exception.respond_to?(:diagnostic)
                 exception.diagnostic.location.line
               end
        data = { file: file, detail: exception.message, line: line }.compact
        send_error(client, id, ERROR_CODES[:syntax_error], "Syntax error in #{file}", data)
      end

      # @private
      # @param [UNIXSocket] client
      # @param [String, Integer, nil] id
      # @param [Integer] code
      # @param [String] message
      # @param [Object?] data optional structured error data
      # @return [void]
      def send_error(client, id, code, message, data = nil)
        error = { code: code, message: message }
        error[:data] = data if data
        response = { jsonrpc: '2.0', id: id, error: error }
        client.write(Protocol.serialize(response))
      end

      # Cleanup socket and PID files on shutdown.
      #
      # @private
      # @raise [StandardError]
      # @return [void]
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
