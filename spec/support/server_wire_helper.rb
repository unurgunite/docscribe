# frozen_string_literal: true

module ServerWireHelper
  def with_unix_server
    Dir.mktmpdir do |dir|
      server = UNIXServer.new("#{dir}/test.sock")
      raw_data = +''
      server_thread = Thread.new { accept_read(server, raw_data) }
      yield "#{dir}/test.sock"
      server_thread.join
      server.close
      raw_data
    end
  end

  private

  def accept_read(server, raw_data)
    c = server.accept
    raw_data.replace(c.read)
    c.close
  end
end
