# frozen_string_literal: true

require 'docscribe/server'
require 'fileutils'
require 'tmpdir'

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

  describe '#ping' do
    it 'returns nil when server is unreachable' do
      expect(client.ping).to be_nil
    end
  end

  describe 'wire format' do
    it 'sends request with single trailing newline', :aggregate_failures do
      raw_data = with_unix_server { |s| described_class.new(s).check(file: 'test.rb') }
      expect(raw_data.count("\n")).to eq(1)
      expect(raw_data).to end_with("\n")
    end
  end
end
