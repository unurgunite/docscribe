# frozen_string_literal: true

require 'socket'

module Docscribe
  module Server
    # Client for communicating with a running Docscribe daemon.
    class Client
      # @param [String, nil] socket_path custom socket path (defaults to server default)
      # @param [String, nil] config_path optional config path for socket lookup
      # @return [void]
      def initialize(socket_path = nil, config_path: nil)
        @socket_path = socket_path || Server.socket_path(config_path)
      end

      # Send a check request to the server.
      #
      # @param [String] file path to file to check
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @param [Hash<Symbol, Object>] rest extra JSON-RPC params (e.g. cli_overrides)
      # @return [Hash<String, Object>, nil] response hash or nil if server unreachable
      def check(file:, strategy: :safe, **rest)
        request('check', file: file, strategy: strategy, **rest)
      end

      # Send a fix request to the server.
      #
      # @param [String] file path to file to fix
      # @param [Symbol] strategy rewrite strategy (:safe, :aggressive)
      # @param [Hash<Symbol, Object>] rest extra JSON-RPC params (e.g. cli_overrides)
      # @return [Hash<String, Object>, nil] response hash or nil if server unreachable
      def fix(file:, strategy: :safe, **rest)
        request('fix', file: file, strategy: strategy, **rest)
      end

      # Send a shutdown request to the server.
      #
      # @return [Hash<String, Object>, nil] response hash or nil if server unreachable
      def shutdown
        request('shutdown')
      end

      # Ping the server and get version/pid/uptime info.
      #
      # @return [Hash<String, Object>, nil] response hash or nil if server unreachable
      def ping
        request('ping')
      end

      private

      # Send a JSON-RPC request and read the response.
      #
      # @private
      # @param [String] method method name
      # @param [Hash<Symbol, Object>] params request parameters
      # @return [Hash<String, Object>, nil]
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
      # @return [T, nil] yield return value or nil on connection error
      def connect
        socket = UNIXSocket.new(@socket_path)
        yield socket
      rescue Errno::ECONNREFUSED, Errno::ENOENT
        nil
      ensure
        socket&.close
      end
    end
  end
end
