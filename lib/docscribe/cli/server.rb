# frozen_string_literal: true

require 'optparse'

module Docscribe
  module CLI
    # Handle the `docscribe server` subcommand.
    module ServerCmd
      BANNER = <<~TEXT
        Usage: docscribe server <command> [options]

        Commands:
          start    Start the background daemon
          stop     Stop the background daemon
          status   Show daemon status

        Options:
          -C, --config <path>    Config file path (default: auto-detect)

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
          config_path, cmd = parse_args(argv)
          return warn(BANNER) || 1 unless cmd

          case cmd
          when 'start' then start_server(config_path)
          when 'stop' then stop_server(config_path)
          when 'status' then show_status(config_path)
          else warn(usage) || 1
          end
        end

        private

        # @private
        # @param [Array<String>] argv
        # @return [(String?, String?)]
        def parse_args(argv)
          config_path = nil
          rest = OptionParser.new do |opts|
            opts.on('-C', '--config <path>', 'Config file path') { |v| config_path = v }
          end.parse!(argv.dup)
          [config_path, rest.first]
        end

        # Start the background daemon process.
        #
        # @private
        # @param [String?] config_path optional config file path
        # @return [Integer] exit code
        def start_server(config_path = nil)
          require 'docscribe/server'
          return already_running(config_path) if Docscribe::Server.running?(config_path)

          Docscribe::Server.ensure_running!(daemonize: true, config_path: config_path)
          pid = Docscribe::Server.read_pid(config_path)
          warn "Docscribe server started (pid #{pid})"
          0
        end

        # @private
        # @param [String?] config_path optional config file path
        # @return [Integer]
        def already_running(config_path = nil)
          pid = Docscribe::Server.read_pid(config_path)
          warn "Docscribe server already running (pid #{pid})"
          0
        end

        # Stop the background daemon.
        #
        # @private
        # @param [String?] config_path optional config file path
        # @return [Integer] exit code
        def stop_server(config_path = nil)
          require 'docscribe/server'
          alive = Docscribe::Server::Client.new(config_path: config_path).shutdown
          warn(alive ? 'Docscribe server stopped' : 'Docscribe server is not running')
          0
        end

        # Show the server status.
        #
        # @private
        # @param [String?] config_path optional config file path
        # @return [Integer] exit code
        def show_status(config_path = nil)
          require 'docscribe/server'
          return warn('Docscribe server is not running') || 0 unless Docscribe::Server.running?(config_path)

          info = Docscribe::Server::Client.new(config_path: config_path).ping
          info ? show_status_from_ping(info) : show_status_fallback(config_path)
          0
        end

        # @private
        # @param [Hash<String, Object>] info ping response hash
        # @return [void]
        def show_status_from_ping(info)
          pid = info.dig('result', 'pid')
          version = info.dig('result', 'version')
          uptime = info.dig('result', 'uptime')
          sock = info.dig('result', 'socket_path')
          warn "Docscribe server v#{version} is running (pid #{pid}, socket #{sock}, uptime #{uptime}s)"
        end

        # @private
        # @param [String?] config_path
        # @return [void]
        def show_status_fallback(config_path)
          pid = Docscribe::Server.read_pid(config_path)
          sock = Docscribe::Server.socket_path(config_path)
          warn "Docscribe server is running (pid #{pid}, socket #{sock})"
        end

        # Print usage information for the server subcommand.
        #
        # @private
        # @return [String]
        def usage
          BANNER
        end
      end
    end
  end
end
