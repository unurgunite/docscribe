# frozen_string_literal: true

require 'socket'
require 'fileutils'
require 'digest/md5'
require 'tmpdir'

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
      def ensure_running!(config_path: nil, daemonize: false, timeout: 15)
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
      def wait_for_ready(config_path: nil, timeout: 15, raise_on_timeout: true) # rubocop:disable SortedMethodsByCall/Waterfall
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
        clean_socket_files(config_path) && false
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

      ENV_FILES = %w[Gemfile.lock rbs_collection.lock.yaml docscribe.yml].freeze
      SIG_RBS_GLOB = 'sig/**/*.rbs'

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
      # so different configs get different daemons, and the config's directory
      # replaces the working directory as the project root.
      # Environment files (Gemfile.lock, rbs_collection.lock.yaml) are also
      # included so daemon is invalidated when gems or RBS types change.
      #
      # @param [String?] config_path optional config path to differentiate
      # @return [String]
      def socket_path(config_path = nil)
        root = project_root(config_path)
        seed = +root
        seed << ":#{env_hash(root)}"
        if config_path
          resolved = File.expand_path(config_path)
          mtime = File.exist?(resolved) ? File.mtime(resolved).to_f : 0.0
          seed << ":#{resolved}:#{mtime}"
        end
        "#{SOCKET_DIR}/docscribe-#{Digest::MD5.hexdigest(seed)}.sock"
      end

      # Directory that environment-file lookups resolve against.
      #
      # When a config path is given, its directory is the project root so a
      # client started from a subdirectory reuses the same daemon. Without a
      # config path this falls back to the working directory.
      #
      # @param [String?] config_path optional config path
      # @return [String] absolute project root path
      def project_root(config_path = nil)
        return File.expand_path(Dir.pwd) unless config_path

        File.expand_path(File.dirname(config_path))
      end

      # Hash of environment files that affect analysis results.
      # When any of these change, the daemon is invalidated (new socket path).
      # Includes Gemfile.lock, rbs_collection.lock.yaml, docscribe.yml and all sig/**/*.rbs.
      #
      # @param [String] root directory containing the environment files
      # @return [String]
      def env_hash(root = File.expand_path(Dir.pwd))
        parts = ENV_FILES.map { |file| env_file_mtime(file, root) }
        parts.concat(sig_env_parts(root))
        Digest::MD5.hexdigest(parts.join(':'))
      end

      # Hash of RBS signature files for cache invalidation inside daemon.
      # Used by Daemon#rewrite_file to detect sig changes without requiring a new socket.
      #
      # @param [String] root directory containing the sig files
      # @return [String]
      def sig_hash(root = File.expand_path(Dir.pwd))
        files = sig_files(root)
        parts = files.map { |p| "#{p}:#{File.mtime(p).to_f}" }
        parts << "count:#{files.size}"
        Digest::MD5.hexdigest(parts.join('|'))
      end

      # @param [String] file
      # @param [String] root directory containing the file
      # @return [String]
      def env_file_mtime(file, root = File.expand_path(Dir.pwd))
        path = File.join(root, file)
        File.exist?(path) ? File.mtime(path).to_f.to_s : '0'
      end

      # @param [String] root directory containing the sig files
      # @return [Array<String>]
      def sig_env_parts(root = File.expand_path(Dir.pwd))
        files = sig_files(root)
        mtimes = files.map { |p| File.mtime(p).to_f.to_s }
        mtimes << files.size.to_s
        mtimes
      end

      # @param [String] root directory containing the sig files
      # @return [Array<String>]
      def sig_files(root = File.expand_path(Dir.pwd))
        Dir.glob(File.join(root, SIG_RBS_GLOB)).sort
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
  end
end
