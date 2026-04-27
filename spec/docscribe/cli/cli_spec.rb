# frozen_string_literal: true

require 'open3'

RSpec.describe 'CLI docscribe' do
  subject(:out) { inline(code) }

  let(:code) do
    <<~RUBY
      class D; def x; 1; end; end
    RUBY
  end

  let(:conf) { Docscribe::Config.new({ 'emit' => { 'return_tag' => false } }) }

  it 'reads from --stdin and outputs docs' do
    Dir.mktmpdir do |dir|
      stdout, status = Open3.capture2('ruby', exe, '--stdin', stdin_data: code, chdir: dir)
      expect(status.success?).to be true
      expect(stdout).to include('# +D#x+')
    end
  end

  it 'respects emit.return_tag override in YAML' do
    expect(conf.emit_return_tag?(:instance, :public)).to be false
  end
end
