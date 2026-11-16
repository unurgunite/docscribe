# frozen_string_literal: true

# Skips examples that need features Windows does not provide.
#
# Server mode is built on AF_UNIX sockets and `Process.fork`, neither of which
# exists on Windows: `Docscribe::Server` refuses to start there by design. The
# whole `spec/docscribe/server` tree and the socket-driven client specs are
# therefore marked with `:unix_socket`, and individual examples that need a
# real fork call `skip_unless_fork!` themselves.
module PlatformHelper
  # Files whose examples all need AF_UNIX sockets plus fork.
  UNIX_SOCKET_SPECS = %w[
    spec/docscribe/server/base_spec.rb
    spec/docscribe/server/client_spec.rb
    spec/docscribe/server/client_status_spec.rb
    spec/docscribe/server/daemon_spec.rb
  ].freeze

  # Skips the example unless AF_UNIX sockets and fork are available.
  #
  # @return [void]
  def skip_unless_unix_sockets!
    skip 'AF_UNIX sockets are unavailable on this platform' unless defined?(UNIXSocket)
    skip 'Process.fork is unavailable on this platform' unless Process.respond_to?(:fork)
  end

  # Skips the example unless `Process.fork` is available.
  #
  # @return [void]
  def skip_unless_fork!
    return if Process.respond_to?(:fork)

    skip 'Process.fork is unavailable on this platform'
  end
end

RSpec.configure do |config|
  config.include PlatformHelper

  config.define_derived_metadata(file_path: %r{/spec/}) do |metadata|
    relative = metadata[:file_path].to_s.sub(%r{\A\./}, '')
    metadata[:unix_socket] = true if PlatformHelper::UNIX_SOCKET_SPECS.include?(relative)
  end

  config.before(:each, :unix_socket) { skip_unless_unix_sockets! }
end
