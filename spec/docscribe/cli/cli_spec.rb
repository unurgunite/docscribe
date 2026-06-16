# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'docscribe/cli'

RSpec.describe Docscribe::CLI do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      class D; def x; 1; end; end
    RUBY
  end

  let(:conf) { Docscribe::Config.new({ 'emit' => { 'return_tag' => false } }) }

  it 'reads from --stdin and outputs docs', :aggregate_failures do
    Dir.mktmpdir do |dir|
      stdout, status = Open3.capture2('ruby', exe, '--stdin', stdin_data: code, chdir: dir)
      expect(status.success?).to be true
      expect(stdout).to include('@return [Integer]')
    end
  end

  it 'respects emit.return_tag override in YAML' do
    expect(conf.emit_return_tag?(:instance, :public)).to be false
  end

  describe '--help' do
    subject(:help) do
      Open3.capture3('ruby', exe, '--help')
    end

    it 'lists init subcommand' do
      expect(help[0]).to include('docscribe init')
    end

    it 'lists generate subcommand' do
      expect(help[0]).to include('docscribe generate')
    end

    it 'lists sigs subcommand' do
      expect(help[0]).to include('docscribe sigs')
    end

    it 'exits 0' do
      expect(help[2].exitstatus).to eq(0)
    end
  end
end
