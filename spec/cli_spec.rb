# frozen_string_literal: true

require 'open3'

RSpec.describe 'CLI docscribe' do
  it 'reads from --stdin and outputs docs' do
    exe = File.expand_path('../exe/docscribe', __dir__)
    code = <<~RUBY
      class D; def x; 1; end; end
    RUBY
    Dir.mktmpdir do |dir|
      stdout, status = Open3.capture2('ruby', exe, '--stdin', stdin_data: code, chdir: dir)
      expect(status.success?).to be true
      expect(stdout).to include('# +D#x+')
    end
  end

  it 'respects emit.return_tag override in YAML' do
    yaml = { 'emit' => { 'return_tag' => false } }
    conf = Docscribe::Config.new(yaml)
    expect(conf.emit_return_tag?(:instance, :public)).to be false
  end
end
