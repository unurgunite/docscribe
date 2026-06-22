# frozen_string_literal: true

module Docscribe
  module CLI
    # Handle the `docscribe server` subcommand.
    module ServerCmd
      BANNER = <<~TEXT
        Usage: docscribe server <command>

        Commands:
          start    Start the background daemon
          stop     Stop the background daemon
          status   Show daemon status

        Once the server is running, use `--server` with other commands:
          docscribe --server check lib/
          docscribe --server --autocorrect lib/
      TEXT

      class << self
        # Run the server subcommand.
        #
        # @param [Array<String>] argv subcommand arguments
        # @return [Integer] exit code
        def run(argv)
          cmd = argv.first

          case cmd
          when 'start' then start_server
          when 'stop' then stop_server
          when 'status' then show_status
          else
            warn usage
            1
          end
        end

        private

        # Start the background daemon process.
        #
        # @private
        # @return [Integer] exit code
        def start_server
          require 'docscribe/server'
          return already_running if Docscribe::Server.running?

          fork_and_wait
          pid = Docscribe::Server.read_pid
          warn "Docscribe server started (pid #{pid})"
          0
        end

        # @private
        # @return [Integer]
        def already_running
          pid = Docscribe::Server.read_pid
          warn "Docscribe server already running (pid #{pid})"
          0
        end

        # @private
        # @return [void]
        def fork_and_wait
          pid = fork do
            $stdin.reopen(File::NULL)
            $stdout.reopen(File::NULL)
            $stderr.reopen(File::NULL)
            daemon = Docscribe::Server::Daemon.new
            daemon.start
          end
          Process.detach(pid)
          wait_for_startup
        end

        # Stop the background daemon.
        #
        # @private
        # @return [Integer] exit code
        def stop_server
          require 'docscribe/server'
          alive = Docscribe::Server::Client.new.shutdown
          warn(alive ? 'Docscribe server stopped' : 'Docscribe server is not running')
          0
        end

        # Show the server status.
        #
        # @private
        # @return [Integer] exit code
        def show_status
          require 'docscribe/server'

          unless Docscribe::Server.running?
            warn 'Docscribe server is not running'
            return 0
          end

          pid = Docscribe::Server.read_pid
          sock = Docscribe::Server.socket_path
          warn "Docscribe server is running (pid #{pid}, socket #{sock})"
          0
        end

        # Print usage information for the server subcommand.
        #
        # @private
        # @return [String]
        def usage
          BANNER
        end

        # Wait for the server to become ready after starting.
        #
        # @private
        # @param [Integer] timeout max seconds to wait
        # @return [void]
        def wait_for_startup(timeout: 5)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          loop do
            break if Docscribe::Server.running?

            if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              warn 'Docscribe server failed to start within timeout'
              break
            end

            sleep 0.1
          end
        end
      end
    end
  end
end
